# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit light-file owners bind a separate locked namespace to independently expected chain/root.
## Only synchronized atomic publication changes the immutable view; uncertain IO requires reopen.
import std/assertions
import ./[light_snapshot, light_state_cache, managed_io, managed_manifest, database_identity,
  file_errors, durability]
import ../codec/state_trie

type
  LightFileConfig* = object ## Caller-selected trust and resource policy never come from on-disk metadata.
    chain*: StorageChainId
    root*: StateRoot
    limits*: LightSnapshotLimits
  LightFileResult*[T] = object ## Refused/default operations never expose an old cache as a successful fresh read.
    case status: FileError
    of None: completed: T
    else: discard
  SelectedImage = object ## One validated read binds its immutable cache and checksum to the same exact bytes.
    cache: LightStateCache
    checksum: StorageChecksum
  FileOwner = ref object ## Stable private lifetime groups one lease, policy and last confirmed immutable cache.
    directory: ManagedDirectory
    config: LightFileConfig
    cache: LightStateCache
    checksum: StorageChecksum
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
proc readCurrent(data: FileOwner): LightFileResult[SelectedImage] =
  ## Read once under the held lease; the checksum and decoded knowledge always describe the same exact bytes.
  let loaded = readManagedFile(data.directory, ManagedFileKind.Current, ManagedEpoch(0),
      data.config.limits.bytes)
  if loaded.error != FileError.None: return LightFileResult[SelectedImage](status: loaded.error)
  let bytes = loaded.value
  let decoded = decodeLightSnapshot(bytes, data.config.chain, data.config.root, data.config.limits)
  let reason = decodedError(decoded.error)
  if reason != FileError.None: return LightFileResult[SelectedImage](status: reason)
  assert bytes.len >= 32
  var checksum = default(array[32, byte])
  for index in 0..<32: checksum[index] = bytes[bytes.len-32+index]
  LightFileResult[SelectedImage](status: FileError.None,
    completed: SelectedImage(cache: decoded.value, checksum: StorageChecksum(checksum)))
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
  data.checksum = loaded.value.checksum
  data.cache = loaded.value.cache
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
  let published = replaceManagedManifest(data.directory, prepared.bytes, config.limits.bytes)
  if published != FileError.None: return LightFileResult[StorageDurability](status: published)
  data.cache = prepared.cache
  data.checksum = prepared.checksum
  owner.data = data
  LightFileResult[StorageDurability](status: FileError.None,
      completed: StorageDurability.FileAndDirectorySynced)
proc snapshot*(owner: LightFileCache): LightFileResult[LightStateCache] =
  ## Return an immutable reader only while this owner has a confirmed selected image.
  let data = owner.data
  if data == nil: return LightFileResult[LightStateCache](status: FileError.Uninitialized)
  if data.poisoned: return LightFileResult[LightStateCache](status: FileError.RecoveryRequired)
  LightFileResult[LightStateCache](status: FileError.None, completed: data.cache)
proc publish*(owner: var LightFileCache, prepared: PreparedLightSnapshot): LightFileResult[
    StorageDurability] =
  ## Atomically replace the selected image only after matching its opaque preparation to the fixed owner policy.
  let data = owner.data
  if data == nil: return LightFileResult[StorageDurability](status: FileError.Uninitialized)
  if data.poisoned: return LightFileResult[StorageDurability](status: FileError.RecoveryRequired)
  let checked = binding(prepared, data.config)
  if checked != FileError.None: return LightFileResult[StorageDurability](status: checked)
  let published = replaceManagedManifest(data.directory, prepared.bytes, data.config.limits.bytes)
  if published != FileError.None:
    # Staging collisions precede mutation; IO uncertainty blocks all fresh observations until validated reopen.
    if published in {FileError.IoFailure, FileError.PublishedUnsynced}: data.poisoned = true
    return LightFileResult[StorageDurability](status: published)
  data.cache = prepared.cache
  data.checksum = prepared.checksum
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
  if array[32, byte](selected.value.checksum) != array[32, byte](data.checksum):
    data.poisoned = true
    return FileError.RecoveryMismatch
  let discarded = discardManagedPending(data.directory)
  if discarded != FileError.None: data.poisoned = true
  discarded
