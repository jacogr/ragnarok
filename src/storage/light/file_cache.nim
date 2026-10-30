# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit light-file owners bind a separate locked namespace to independently expected chain/root.
## Only synchronized atomic publication changes the immutable view; uncertain IO requires reopen.
import std/assertions
import ./[snapshot as light_snapshot, state_cache as light_state_cache]
import ../managed/[io as managed_io, manifest as managed_manifest]
import ../database_identity
import ../file/errors as file_errors
import ../durability
import ../../codec/state/[trie as state_trie, layout as state_layout]

type
  LightFileConfig* = object ## Caller-selected trust and resource policy never come from on-disk metadata.
    chain*: StorageChainId
    root*: StateRoot
    limits*: LightSnapshotLimits
  LightFileResult*[T] = object ## Refused/default operations never expose an old cache as a successful fresh read.
    case status: FileError
    of None: completed: T
    else: discard
  FileOwner = ref object ## Stable private lifetime groups one lease, policy and last confirmed immutable cache.
    directory: ManagedDirectory
    config: LightFileConfig
    image: PreparedLightSnapshot
    poisoned: bool
  LightFileCache* = object ## Exclusive explicit retirement authority; immutable cache readers do not retain its lease.
    data: nil FileOwner

proc `=copy`*(destination: var LightFileCache, source: LightFileCache) {.error.}
  ## Duplicating a ref-backed composite would create a second native retirement authority.

proc `=dup`*(source: LightFileCache): LightFileCache {.error.}
  ## Reject hidden duplication during actual ARC lowering as well as explicit copy.

proc requireClosed(owner: LightFileCache) {.requires: owner.data == nil.} =
  ## Close errors must remain observable instead of silently retiring a lock in destruction.
  discard

proc `=wasMoved`*(owner: var LightFileCache) {.nodestroy, inline.} =
  ## Disarm transferred fields through their own move hooks; never destroy the destination resources.
  `=wasMoved`(owner.data)

proc `=destroy`*(owner: LightFileCache) =
  ## Compiler-generated moves leave a nil sentinel; destruction of an unclosed owner is misuse.
  requireClosed(owner)
  `=destroy`(owner.data)

func error*[T](outcome: LightFileResult[T]): FileError =
  ## Observe refusal without exposing private result state.
  outcome.status

func value*[T](outcome: LightFileResult[T]): T {.inline,
    requires: outcome.status == FileError.None.} =
  ## Extract immutable readers or synchronization receipts only from completed operations.
  outcome.completed

func opened*(owner: LightFileCache): bool =
  ## Poll lifecycle safely even for default and moved-from owners.
  owner.data != nil

proc close*(owner: var LightFileCache): FileError =
  ## Release exactly one directory lease, including poisoned owners, and disarm even after native close refusal.
  let data = owner.data
  if data == nil: return FileError.Uninitialized
  let retired = data.directory.close
  owner.data = nil
  retired

func samePolicy(left, right: LightSnapshotLimits): bool =
  ## Every scalar resource ceiling, including ordinary mutation policy, is part of preparation identity.
  uint64(left.bytes) == uint64(right.bytes) and
    uint64(left.cache.items) == uint64(right.cache.items) and
    uint64(left.cache.writes) == uint64(right.cache.writes) and
    uint64(left.cache.valueBytes) == uint64(right.cache.valueBytes) and
    uint64(left.cache.proof.nodes) == uint64(right.cache.proof.nodes) and
    uint64(left.cache.proof.valueBytes) == uint64(right.cache.proof.valueBytes)

proc binding(prepared: PreparedLightSnapshot, config: LightFileConfig): FileError =
  ## Refuse unprepared, unrelated or differently bounded images before filesystem mutation.
  if not prepared.initialized: return FileError.Uninitialized
  if array[32, byte](prepared.chainId) != array[32, byte](config.chain) or
      array[32, byte](prepared.root) != array[32, byte](config.root):
    return FileError.WrongIdentity
  if not samePolicy(prepared.limits, config.limits): return FileError.InvalidBatch
  FileError.None

func decodedError(reason: LightSnapshotError): FileError =
  ## Preserve broad typed IO-domain distinctions without granting any partially decoded payload.
  case reason
  of LightSnapshotError.None: FileError.None
  of LightSnapshotError.WrongChain, LightSnapshotError.WrongRoot: FileError.WrongIdentity
  of LightSnapshotError.LimitExceeded, LightSnapshotError.LengthOverflow: FileError.LimitExceeded
  of LightSnapshotError.BackendFailure: FileError.BackendFailure
  else: FileError.InvalidFrame

proc readCurrent(data: FileOwner): LightFileResult[PreparedLightSnapshot] =
  ## Retain the exact fully verified selected image so later admission need not resubmit old evidence.
  var loaded = readManagedFile(data.directory, ManagedFileKind.Current, ManagedEpoch(0),
      data.config.limits.bytes)
  if loaded.error != FileError.None: return LightFileResult[PreparedLightSnapshot](
      status: loaded.error)
  var encoded = loaded.takeValue
  let restored = takeLightSnapshot(encoded, data.config.chain, data.config.root, data.config.limits)
  let reason = decodedError(restored.error)
  if reason != FileError.None: return LightFileResult[PreparedLightSnapshot](status: reason)
  LightFileResult[PreparedLightSnapshot](status: FileError.None, completed: restored.value)

proc openLightFileCache*(owner: var LightFileCache, path: string,
    config: LightFileConfig): FileError =
  ## Acquire an existing namespace and verify its complete image against explicit independent expectations.
  if owner.opened: return FileError.Busy
  var data = FileOwner(config: config)
  let acquired = openManagedDirectory(data.directory, path)
  if acquired != FileError.None: return acquired
  defer:
    if owner.data == nil: discard data.directory.close # Refused opens retire the lease without selecting fallback bytes.
  let loaded = readCurrent(data)
  if loaded.error != FileError.None: return loaded.error
  data.image = loaded.value
  owner.data = data
  FileError.None

proc initializeLightFileCache*(owner: var LightFileCache, path: string, config: LightFileConfig,
    prepared: PreparedLightSnapshot): LightFileResult[StorageDurability] =
  ## Create a new private namespace only from a fully prepared image with the exact trust/policy binding.
  if owner.opened: return LightFileResult[StorageDurability](status: FileError.Busy)
  let checked = binding(prepared, config)
  if checked != FileError.None: return LightFileResult[StorageDurability](status: checked)
  var data = FileOwner(config: config)
  let acquired = initializeManagedDirectory(data.directory, path)
  if acquired != FileError.None: return LightFileResult[StorageDurability](status: acquired)
  defer:
    if owner.data == nil: discard data.directory.close # Failed bootstrap leaves forensic files but no live authority.
  let published = replaceManagedManifest(data.directory, prepared.encodedBytes, config.limits.bytes)
  if published != FileError.None: return LightFileResult[StorageDurability](status: published)
  data.image = prepared
  owner.data = data
  LightFileResult[StorageDurability](status: FileError.None,
      completed: StorageDurability.FileAndDirectorySynced)

proc snapshot*(owner: LightFileCache): LightFileResult[LightStateCache] =
  ## Return an immutable reader only while this owner has a confirmed selected image.
  let data = owner.data
  if data == nil: return LightFileResult[LightStateCache](status: FileError.Uninitialized)
  if data.poisoned: return LightFileResult[LightStateCache](status: FileError.RecoveryRequired)
  LightFileResult[LightStateCache](status: FileError.None, completed: data.image.cache)

proc preparedSnapshot*(owner: LightFileCache): LightFileResult[PreparedLightSnapshot] =
  ## Retain selected immutable proof evidence without IO or a new durability receipt; no directory lease escapes.
  let data = owner.data
  if data == nil: return LightFileResult[PreparedLightSnapshot](status: FileError.Uninitialized)
  if data.poisoned: return LightFileResult[PreparedLightSnapshot](
      status: FileError.RecoveryRequired)
  LightFileResult[PreparedLightSnapshot](status: FileError.None, completed: data.image)

proc publish*(owner: var LightFileCache, prepared: PreparedLightSnapshot): LightFileResult[
    StorageDurability] =
  ## Atomically replace the selected image only after matching its opaque preparation to the fixed owner policy.
  let data = owner.data
  if data == nil: return LightFileResult[StorageDurability](status: FileError.Uninitialized)
  if data.poisoned: return LightFileResult[StorageDurability](status: FileError.RecoveryRequired)
  let checked = binding(prepared, data.config)
  if checked != FileError.None: return LightFileResult[StorageDurability](status: checked)
  let published = replaceManagedManifest(data.directory, prepared.encodedBytes,
      data.config.limits.bytes)
  if published != FileError.None:
    # Staging collisions precede mutation; IO uncertainty blocks all fresh observations until validated reopen.
    if published in {FileError.IoFailure, FileError.PublishedUnsynced}: data.poisoned = true
    return LightFileResult[StorageDurability](status: published)
  data.image = prepared
  LightFileResult[StorageDurability](status: FileError.None,
      completed: StorageDurability.FileAndDirectorySynced)

proc discardPending*(owner: var LightFileCache): FileError =
  ## Revalidate the selected image before explicitly removing an unselected regular staging file.
  let data = owner.data
  if data == nil: return FileError.Uninitialized
  if data.poisoned: return FileError.RecoveryRequired
  let selected = readCurrent(data)
  if selected.error != FileError.None:
    data.poisoned = true # Invalid or unreadable selected bytes cannot authorize cleanup or fresh cache reads.
    return selected.error
  if array[32, byte](selected.value.checksum) != array[32, byte](data.image.checksum):
    data.poisoned = true
    return FileError.RecoveryMismatch
  let discarded = discardManagedPending(data.directory)
  if discarded != FileError.None: data.poisoned = true
  discarded

proc admit*(owner: var LightFileCache, updates: openArray[LightStateProof]): LightFileResult[
    StorageDurability] =
  ## Authenticate incoming proof evidence privately, then publish through the same atomic synchronized file path.
  let data = owner.data
  if data == nil: return LightFileResult[StorageDurability](status: FileError.Uninitialized)
  if data.poisoned: return LightFileResult[StorageDurability](status: FileError.RecoveryRequired)
  let edited = data.image.admit(updates)
  let reason = decodedError(edited.error)
  if reason != FileError.None: return LightFileResult[StorageDurability](status: reason)
  owner.publish(edited.value)

proc forget*(owner: var LightFileCache, keys: openArray[StateKey]): LightFileResult[
    StorageDurability] =
  ## Durably drop only local evidence; the unchanged root never derives from the remaining partial cache.
  let data = owner.data
  if data == nil: return LightFileResult[StorageDurability](status: FileError.Uninitialized)
  if data.poisoned: return LightFileResult[StorageDurability](status: FileError.RecoveryRequired)
  let edited = data.image.forget(keys)
  let reason = decodedError(edited.error)
  if reason != FileError.None: return LightFileResult[StorageDurability](status: reason)
  owner.publish(edited.value)

proc update*(owner: var LightFileCache, proofs: openArray[LightStateProof],
    forgottenKeys: openArray[StateKey]): LightFileResult[StorageDurability] =
  ## Atomically replace local evidence at capacity through one validated image and one synchronized publication.
  let data = owner.data
  if data == nil: return LightFileResult[StorageDurability](status: FileError.Uninitialized)
  if data.poisoned: return LightFileResult[StorageDurability](status: FileError.RecoveryRequired)
  let edited = data.image.update(proofs, forgottenKeys)
  let reason = decodedError(edited.error)
  if reason != FileError.None: return LightFileResult[StorageDurability](status: reason)
  owner.publish(edited.value)
