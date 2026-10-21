# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Synchronous exclusive-owner disk coordination: publish nodes/context before canonical or RPC installation.
## Call only during startup or on an explicitly excluded native worker, never from dispatcher callbacks.
import ./[chain, disk_history]
import ../chain/[genesis, provider, parameters]
import ../state/[store, disk_store, accumulation_publication]
import ../storage/[file_repository, node_repository, database_identity]
import ../codec/bounded
import ../rpc/server as rpc_server

type
  PreparedDiskPublication* = object ## Opaque immutable context and exact-parent authority may cross one exclusive worker lease.
    initialized: bool
    parent: StateStoreSnapshot
    update: PreparedChainUpdate
    context: seq[byte]
    next: RepositoryGeneration
  DiskChainError* {.pure.} = enum ## Default/refused results grant no partial canonical successor.
    Uninitialized, None, Busy, CanonicalMismatch, GenerationOverflow, StoreFailure, ContextFailure, FileFailure
  DiskChainResult*[T] = object ## Preserve actual storage IO uncertainty and context refusals behind guarded access.
    case status: DiskChainError
    of None: completed: T
    of StoreFailure: storeReason: DiskStoreResult[StateStoreSnapshot]
    of ContextFailure: contextReason: DiskHistoryError
    of FileFailure: fileReason: FileError
    else: discard # Canonical mismatch and default outcomes have no candidate payload.

const BootstrapMagic = "RAGNAROK-DISK-BOOTSTRAP-V1\n" # Deliberately cannot decode as a canonical disk history.
func error*[T](outcome: DiskChainResult[T]): DiskChainError =
  ## Observe only the selected outer stage.
  outcome.status
func value*[T](outcome: DiskChainResult[T]): T {.inline,
    requires: outcome.status == DiskChainError.None.} =
  ## Access only a confirmed durable generation or fully restored canonical owner.
  outcome.completed
func storeFailure*[T](outcome: DiskChainResult[T]): DiskStoreResult[StateStoreSnapshot] {.requires:
    outcome.status == DiskChainError.StoreFailure.} =
  ## Preserve the actual failed disk operation, including its typed IO uncertainty.
  outcome.storeReason
func contextError*[T](outcome: DiskChainResult[T]): DiskHistoryError {.requires:
    outcome.status == DiskChainError.ContextFailure.} =
  ## Inspect only the selected bounded-history failure.
  outcome.contextReason
func fileError*[T](outcome: DiskChainResult[T]): FileError {.requires:
    outcome.status == DiskChainError.FileFailure.} =
  ## Inspect only an actual context-read IO failure.
  outcome.fileReason
proc initializeDiskChain*(disk: var DiskStateStore, path: string, chain: StorageChainId,
    owner: ApplicationChain, limits: JournalLimits): DiskChainResult[RepositoryGeneration] =
  ## Exclusive creation provisions at most nine complete roots, then one atomic canonical context.
  ## Intermediate bootstrap frames are forensic evidence, never a resumable canonical fallback.
  if disk.opened: return DiskChainResult[RepositoryGeneration](status: DiskChainError.Busy)
  let current = owner.stateSnapshot
  let view = owner.chainView
  if current.error != StateStoreError.None or view.retainedCount == 0:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  var sources: seq[StateStoreSnapshot] = @[]
  let finalized = view.finalizedBlock
  var inside = false
  if finalized.error == GenesisError.None:
    for index in 0..<view.retainedCount:
      if array[32, byte](view.retainedBlockAt(RetainedBlockIndex(index)).value.blockHash) ==
          array[32, byte](finalized.value.blockHash): inside = true
    if not inside: sources.add(finalized.value.stateSnapshot)
  for index in 0..<view.retainedCount:
    sources.add(view.retainedBlockAt(RetainedBlockIndex(index)).value.stateSnapshot)
  for source in sources:
    if not sameStateStorePolicy(current.value, source):
      return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  let generation = RepositoryGeneration(uint64(sources.len)+1)
  let context = encodeDiskHistory(owner, chain, generation, limits.contextBytes)
  if context.error != DiskHistoryError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.ContextFailure,
      contextReason: context.error)
  var bootstrap: seq[byte] = @[]
  for character in BootstrapMagic: bootstrap.add(byte(character))
  var adopted = false
  defer:
    if not adopted and disk.opened: discard disk.close # Preserve failed bootstrap bytes, but release every owned lock.
  let initialized = initializeDiskStateStore(disk, path, chain, sources[0], limits,
    StorageSchema.FullStateV1, bootstrap)
  if initialized.error != DiskStoreError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.StoreFailure,
      storeReason: initialized)
  for index in 1..<sources.len:
    let provisioned = disk.commit(disk.snapshot.value, sources[index], bootstrap)
    if provisioned.error != DiskStoreError.None:
      return DiskChainResult[RepositoryGeneration](status: DiskChainError.StoreFailure,
        storeReason: provisioned)
  let selected = disk.commit(disk.snapshot.value, current.value, context.value)
  if selected.error != DiskStoreError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.StoreFailure,
        storeReason: selected)
  adopted = true
  DiskChainResult[RepositoryGeneration](status: DiskChainError.None, completed: generation)
proc openDiskChain*(disk: var DiskStateStore, path: string, chain: StorageChainId,
    configuration: Parameters, policy: StateStoreLimits,
    limits: JournalLimits): DiskChainResult[ApplicationChain] =
  ## Normal restart trusts only this complete local journal and exact configured chain/profile.
  ## No external-import fallback, repair, truncation or silent bootstrap adoption occurs.
  if disk.opened: return DiskChainResult[ApplicationChain](status: DiskChainError.Busy)
  let acquired = openLocalDiskStateStore(disk, path, chain, policy, limits)
  if acquired.error != DiskStoreError.None:
    return DiskChainResult[ApplicationChain](status: DiskChainError.StoreFailure,
        storeReason: acquired)
  var adopted = false
  defer:
    if not adopted: discard disk.close # Failed application binding cannot retain a usable disk execution owner.
  let context = disk.snapshotContext
  if context.error != FileError.None:
    return DiskChainResult[ApplicationChain](status: DiskChainError.FileFailure,
        fileReason: context.error)
  let restored = restoreDiskHistory(context.value, chain, disk.generation.value,
    configuration, disk, policy, limits.contextBytes)
  if restored.error != DiskHistoryError.None:
    return DiskChainResult[ApplicationChain](status: DiskChainError.ContextFailure,
      contextReason: restored.error)
  adopted = true
  DiskChainResult[ApplicationChain](status: DiskChainError.None, completed: restored.value)
proc prepareContext(disk: DiskStateStore, owner: ApplicationChain, prepared: PreparedChainUpdate,
    chain: StorageChainId, limit: ByteLimit): DiskChainResult[seq[byte]] =
  ## Preflight exact canonical/disk authority and all fallible context encoding before IO begins.
  let current = disk.snapshot
  if not owner.canInstallPrepared(prepared) or current.error != DiskStoreError.None or
      not sameStateSnapshot(current.value, owner.stateSnapshot.value):
    return DiskChainResult[seq[byte]](status: DiskChainError.CanonicalMismatch)
  let generation = disk.generation
  if generation.error != DiskStoreError.None or uint64(generation.value) == high(uint64):
    return DiskChainResult[seq[byte]](status: DiskChainError.GenerationOverflow)
  let selected = disk.snapshotContext
  if selected.error != FileError.None:
    return DiskChainResult[seq[byte]](status: DiskChainError.FileFailure,
        fileReason: selected.error)
  let previous = encodeDiskHistory(owner, chain, generation.value, limit)
  if previous.error != DiskHistoryError.None:
    return DiskChainResult[seq[byte]](status: DiskChainError.ContextFailure,
        contextReason: previous.error)
  if previous.value != selected.value:
    return DiskChainResult[seq[byte]](status: DiskChainError.CanonicalMismatch)
  let target = initApplicationChain(prepared.chainView)
  if target.error != ApplicationChainError.None:
    return DiskChainResult[seq[byte]](status: DiskChainError.CanonicalMismatch)
  let context = encodeDiskHistory(target.value, chain,
    RepositoryGeneration(uint64(generation.value)+1), limit)
  if context.error != DiskHistoryError.None:
    return DiskChainResult[seq[byte]](status: DiskChainError.ContextFailure,
        contextReason: context.error)
  DiskChainResult[seq[byte]](status: DiskChainError.None, completed: context.value)
func ready*(publication: PreparedDiskPublication): bool =
  ## Defaults never authorize worker publication or canonical update access.
  publication.initialized
func chainUpdate*(publication: PreparedDiskPublication): PreparedChainUpdate {.requires:
    publication.initialized.} =
  ## Retain the original opaque update for host installation after a confirmed durable receipt.
  publication.update
proc prepareDiskPublication*(disk: DiskStateStore, owner: ApplicationChain,
    prepared: PreparedChainUpdate, chain: StorageChainId,
    limit: ByteLimit): DiskChainResult[PreparedDiskPublication] =
  ## Stage bounded context without journal mutation; caller must also preflight enabled RPC and hold exclusion.
  let context = prepareContext(disk, owner, prepared, chain, limit)
  if context.error != DiskChainError.None:
    case context.error
    of DiskChainError.ContextFailure:
      return DiskChainResult[PreparedDiskPublication](status: DiskChainError.ContextFailure,
        contextReason: context.contextError)
    of DiskChainError.FileFailure:
      return DiskChainResult[PreparedDiskPublication](status: DiskChainError.FileFailure,
        fileReason: context.fileError)
    of DiskChainError.GenerationOverflow:
      return DiskChainResult[PreparedDiskPublication](status: DiskChainError.GenerationOverflow)
    else:
      return DiskChainResult[PreparedDiskPublication](status: DiskChainError.CanonicalMismatch)
  DiskChainResult[PreparedDiskPublication](status: DiskChainError.None,
    completed: PreparedDiskPublication(initialized: true, parent: owner.stateSnapshot.value,
      update: prepared, context: context.value,
      next: RepositoryGeneration(uint64(disk.generation.value)+1)))
proc commitDiskPublication*(disk: var DiskStateStore,
    publication: PreparedDiskPublication): DiskChainResult[RepositoryGeneration] =
  ## Perform synchronous IO only under exclusive ownership; this never touches application or RPC objects.
  ## A reused context-only parent still requires the exact expected journal generation.
  if not publication.initialized:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  let generation = disk.generation
  if generation.error != DiskStoreError.None or uint64(generation.value) != uint64(
      publication.next)-1:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  let committed = disk.commit(publication.parent, publication.update.stateSnapshot,
      publication.context)
  if committed.error != DiskStoreError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.StoreFailure,
        storeReason: committed)
  DiskChainResult[RepositoryGeneration](status: DiskChainError.None, completed: publication.next)
proc stageFailure(failed: DiskChainResult[PreparedDiskPublication]): DiskChainResult[
    RepositoryGeneration] =
  ## Propagate only actual guarded preparation refusals without synthesizing missing variant payloads.
  case failed.error
  of DiskChainError.ContextFailure:
    DiskChainResult[RepositoryGeneration](status: DiskChainError.ContextFailure,
        contextReason: failed.contextError)
  of DiskChainError.FileFailure:
    DiskChainResult[RepositoryGeneration](status: DiskChainError.FileFailure,
        fileReason: failed.fileError)
  of DiskChainError.GenerationOverflow:
    DiskChainResult[RepositoryGeneration](status: DiskChainError.GenerationOverflow)
  else:
    DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
proc publishDiskChain*(disk: var DiskStateStore, owner: var ApplicationChain,
    prepared: PreparedChainUpdate, chain: StorageChainId,
    limit: ByteLimit): DiskChainResult[RepositoryGeneration] =
  ## Stable exclusive owners span preflight/fsync/install; failure never advances the application.
  let staged = prepareDiskPublication(disk, owner, prepared, chain, limit)
  if staged.error != DiskChainError.None: return stageFailure(staged)
  let committed = commitDiskPublication(disk, staged.value)
  if committed.error != DiskChainError.None: return committed
  owner.installPrepared(prepared) # No execution, capture or typed fallible composition remains after fsync.
  committed
proc publishDiskChain*(disk: var DiskStateStore, owner: var ApplicationChain,
    rpc: var rpc_server.Server, prepared: PreparedChainUpdate, chain: StorageChainId,
    limit: ByteLimit, lease: nil rpc_server.RpcChainLease = nil): DiskChainResult[
        RepositoryGeneration] =
  ## Enabled RPC participates in the exact same durable publication; refusal never falls back silently.
  if not owner.canInstallPrepared(rpc, prepared, lease):
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  let staged = prepareDiskPublication(disk, owner, prepared, chain, limit)
  if staged.error != DiskChainError.None: return stageFailure(staged)
  let committed = commitDiskPublication(disk, staged.value)
  if committed.error != DiskChainError.None: return committed
  owner.installPrepared(rpc, prepared, lease) # Canonical/RPC visibility follows confirmed durability under exclusion.
  committed
