# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Synchronous exclusive-owner disk coordination: publish nodes/context before canonical or RPC installation.
## Call only during startup or on an explicitly excluded native worker, never from dispatcher callbacks.
import std/assertions
import ./[chain, disk_history, disk_sources, paged_policy, historical_context, historical_disk]
import ../chain/[genesis, provider, parameters]
import ../state/[store, disk_store, accumulation_publication, accumulation_current_update]
import ../storage/[file_repository, node_repository, database_identity, managed_repository,
    managed_manifest, history_index, history_files, full_paged_store]
import ../codec/[bounded, state_trie]
import ../rpc/server as rpc_server

type
  PreparedDiskPublication* = object ## Opaque immutable context and exact-parent authority may cross one exclusive worker lease.
    initialized: bool
    parent: StateStoreSnapshot
    update: PreparedChainUpdate
    context, previous: seq[byte]
    history: seq[StateStoreSnapshot]
    historical: PreparedHistoricalRecord # Fixed append metadata and one exact source, never the archive catalog.
    replay: bool
    next: RepositoryGeneration
  CurrentDiskPublicationData = ref object # One immutable current update and its validated disk context are retained together.
    parent: StateStoreSnapshot
    update: PreparedCurrentChainUpdate
    context, previous: seq[byte]
    history: seq[StateStoreSnapshot]
    historical: PreparedHistoricalRecord # Fixed append metadata and one exact source, never the archive catalog.
    replay: bool
    next: RepositoryGeneration
  PreparedCurrentDiskPublication* = object ## Defaults grant no current-PVM publication or update extraction authority.
    data: nil CurrentDiskPublicationData
  DiskPublicationContext = object # Preflight captures each validated generation/context once for either update family.
    bytes, previous: seq[byte]
    history: seq[StateStoreSnapshot]
    historical: PreparedHistoricalRecord # Fixed append metadata and one exact source, never the archive catalog.
    next: RepositoryGeneration
  PreparedDiskMaintenance* = object ## Exact canonical context, state revision and physical epoch authorize one excluded maintenance attempt.
    initialized: bool
    parent: StateStoreSnapshot
    generation: RepositoryGeneration
    epoch: ManagedEpoch
    context: seq[byte]
    roots: seq[StateRoot]
  DiskChainError* {.pure.} = enum ## Default/refused results grant no partial canonical successor.
    Uninitialized, None, Busy, CanonicalMismatch, GenerationOverflow, StoreFailure, ContextFailure,
      FileFailure, MaintenanceFailure, HistoryFailure
  DiskChainResult*[T] = object ## Preserve actual storage IO uncertainty and context refusals behind guarded access.
    case status: DiskChainError
    of None: completed: T
    of StoreFailure: storeReason: DiskStoreResult[StateStoreSnapshot]
    of ContextFailure: contextReason: DiskHistoryError
    of FileFailure: fileReason: FileError
    of MaintenanceFailure: maintenanceReason: DiskStoreResult[ManagedCompaction]
    of HistoryFailure: historyReason: HistoryError
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
func maintenanceFailure*[T](outcome: DiskChainResult[T]): DiskStoreResult[
    ManagedCompaction] {.requires:
    outcome.status == DiskChainError.MaintenanceFailure.} =
  ## Only an actual failed managed physical replacement exposes its guarded nested reason.
  outcome.maintenanceReason
func historyError*[T](outcome: DiskChainResult[T]): HistoryError {.requires:
    outcome.status == DiskChainError.HistoryFailure.} =
  ## Historical file/codec/counter failures never expose a usable successor or ordinary IO receipt.
  outcome.historyReason
proc diskSources(owner: ApplicationChain): DiskChainResult[seq[StateStoreSnapshot]] =
  ## Reuse one live validation/finality root contract across normal publication and historical policy changes.
  let sources = liveDiskSources(owner)
  if sources.error != HistoryError.None:
    return DiskChainResult[seq[StateStoreSnapshot]](status: DiskChainError.CanonicalMismatch)
  DiskChainResult[seq[StateStoreSnapshot]](status: DiskChainError.None, completed: sources.value)
proc initializePagedDiskChain*(disk: var DiskStateStore, path: string, chain: StorageChainId,
    owner: ApplicationChain, limits: JournalLimits, replay = false): DiskChainResult[
        RepositoryGeneration] =
  ## Exclusive V2 bootstrap selects current state, exact rolling/finalized roots and complete application context in one artifact.
  if disk.opened: return DiskChainResult[RepositoryGeneration](status: DiskChainError.Busy)
  let captured = diskSources(owner)
  if captured.error != DiskChainError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  let sources = captured.value
  var history: seq[StateStoreSnapshot] = @[]
  for index in 0..<sources.len-1: history.add(sources[
      index]) # The current complete snapshot is always the last independently captured source.
  let generation = RepositoryGeneration(1)
  let policy = pagedApplicationPolicy(chain, owner.stateSnapshot.value.commitment.root, limits)
  let context = encodeDiskHistory(owner, chain, generation, policy.contextBytes)
  if context.error != DiskHistoryError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.ContextFailure,
        contextReason: context.error)
  let initialized = if replay:
    resumePagedDiskStateStore(disk, path, owner.stateSnapshot.value, policy.native,
        policy.transport, context.value, history)
  else:
    initializePagedDiskStateStore(disk, path, owner.stateSnapshot.value, policy.native,
        policy.transport, context.value, history) # Ordinary bootstrap preserves exclusive creation.
  if initialized.error != DiskStoreError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.StoreFailure,
        storeReason: initialized)
  DiskChainResult[RepositoryGeneration](status: DiskChainError.None, completed: generation)
proc initializeDiskChain*(disk: var DiskStateStore, path: string, chain: StorageChainId,
    owner: ApplicationChain, limits: JournalLimits): DiskChainResult[RepositoryGeneration] =
  ## Exclusive creation provisions the configured rolling roots/finality, then one atomic canonical context.
  ## Intermediate bootstrap frames are forensic evidence, never a resumable canonical fallback.
  if disk.opened: return DiskChainResult[RepositoryGeneration](status: DiskChainError.Busy)
  let current = owner.stateSnapshot
  let captured = diskSources(owner)
  if captured.error != DiskChainError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  let sources = captured.value
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
proc initializeManagedDiskChain*(disk: var DiskStateStore, path: string, chain: StorageChainId,
    owner: ApplicationChain, limits: ManagedLimits): DiskChainResult[RepositoryGeneration] =
  ## All rolling roots, explicit finality and canonical context are admitted before publishing one managed epoch.
  if disk.opened: return DiskChainResult[RepositoryGeneration](status: DiskChainError.Busy)
  let captured = diskSources(owner)
  if captured.error != DiskChainError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  let sources = captured.value
  let generation = RepositoryGeneration(uint64(sources.len))
  let context = encodeDiskHistory(owner, chain, generation, limits.contextBytes)
  if context.error != DiskHistoryError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.ContextFailure,
        contextReason: context.error)
  var history: seq[StateStoreSnapshot] = @[]
  for index in 0..<sources.len-1: history.add(sources[index])
  let initialized = initializeManagedDiskStateStore(disk, path, chain, owner.stateSnapshot.value,
    limits, StorageSchema.FullStateV1, context.value, history)
  if initialized.error != DiskStoreError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.StoreFailure,
        storeReason: initialized)
  assert uint64(disk.generation.value) == uint64(generation)
  DiskChainResult[RepositoryGeneration](status: DiskChainError.None, completed: generation)
proc acquireDiskChain(disk: var DiskStateStore, path: string, chain: StorageChainId,
    configuration: Parameters, policy: StateStoreLimits,
    limits: JournalLimits, managed: bool, physical: ManagedLimits, paged = false): DiskChainResult[
        ApplicationChain] =
  ## Normal restart trusts only this complete local journal and exact configured chain/profile.
  ## No external-import fallback, repair, truncation or silent bootstrap adoption occurs.
  if disk.opened: return DiskChainResult[ApplicationChain](status: DiskChainError.Busy)
  let bounded = pagedApplicationPolicy(chain, default(StateRoot), limits)
  let acquired = if paged:
    openLocalPagedDiskStateStore(disk, path, chain, policy, bounded.native, bounded.transport)
  elif managed:
    openLocalManagedDiskStateStore(disk, path, chain, policy, physical)
  else:
    openLocalDiskStateStore(disk, path, chain, policy, limits)
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
  if hasHistoricalContext(context.value):
    let checked = checkedDiskHistory(disk, restored.value, chain, limits.contextBytes)
    if checked.error != HistoryError.None:
      return DiskChainResult[ApplicationChain](status: DiskChainError.HistoryFailure,
          historyReason: checked.error)
    discard completeHistorySelection(disk, checked.value.historyCursor,
        checked.value) # Reclaim only already unselected files; cleanup diagnostics remain separate from canonical recovery.
  adopted = true
  DiskChainResult[ApplicationChain](status: DiskChainError.None, completed: restored.value)
proc openDiskChain*(disk: var DiskStateStore, path: string, chain: StorageChainId,
    configuration: Parameters, policy: StateStoreLimits,
    limits: JournalLimits): DiskChainResult[ApplicationChain] =
  ## Existing single-file startup keeps its strict local-head and application context binding.
  acquireDiskChain(disk, path, chain, configuration, policy, limits, false, default(ManagedLimits))
proc openManagedDiskChain*(disk: var DiskStateStore, path: string, chain: StorageChainId,
    configuration: Parameters, policy: StateStoreLimits,
    limits: ManagedLimits): DiskChainResult[ApplicationChain] =
  ## Managed startup resumes only after the same profile, history, map and explicit finality checks.
  let journal = JournalLimits(repository: limits.repository, bytes: limits.journalBytes,
      contextBytes: limits.contextBytes)
  acquireDiskChain(disk, path, chain, configuration, policy, journal, true, limits)
proc openPagedDiskChain*(disk: var DiskStateStore, path: string, chain: StorageChainId,
    configuration: Parameters, policy: StateStoreLimits,
    limits: JournalLimits): DiskChainResult[ApplicationChain] =
  ## Only a completely admitted V2 local graph plus exact profile/history/finality binding yields a canonical application owner.
  acquireDiskChain(disk, path, chain, configuration, policy, limits, false, default(ManagedLimits), true)
proc prepareContextView(disk: DiskStateStore, owner: ApplicationChain, view: ChainView,
    chain: StorageChainId, limit: ByteLimit): DiskChainResult[DiskPublicationContext] =
  ## Preflight exact canonical/disk authority and all fallible context encoding before IO begins.
  if owner.chainView.hasHistoricalIndex or view.hasHistoricalIndex:
    return DiskChainResult[DiskPublicationContext](
        status: DiskChainError.CanonicalMismatch) # A resident memory archive requires explicit migration, not a silent disk adoption.
  let maximum = ByteLimit(min(uint64(limit), uint64(disk.applicationContextLimit)))
  let current = disk.snapshot
  let canonical = owner.stateSnapshot
  if current.error != DiskStoreError.None or canonical.error != StateStoreError.None or
      not sameStateSnapshot(current.value, canonical.value):
    return DiskChainResult[DiskPublicationContext](status: DiskChainError.CanonicalMismatch)
  let generation = disk.generation
  if generation.error != DiskStoreError.None or uint64(generation.value) == high(uint64):
    return DiskChainResult[DiskPublicationContext](status: DiskChainError.GenerationOverflow)
  let selected = disk.snapshotContext
  if selected.error != FileError.None:
    return DiskChainResult[DiskPublicationContext](status: DiskChainError.FileFailure,
        fileReason: selected.error)
  let previous = encodeMatchingDiskHistory(owner, chain, generation.value, maximum, selected.value)
  if previous.error != DiskHistoryError.None:
    return DiskChainResult[DiskPublicationContext](status: DiskChainError.ContextFailure,
        contextReason: previous.error)
  if previous.value != selected.value:
    return DiskChainResult[DiskPublicationContext](status: DiskChainError.CanonicalMismatch)
  let target = initApplicationChain(view)
  if target.error != ApplicationChainError.None:
    return DiskChainResult[DiskPublicationContext](status: DiskChainError.CanonicalMismatch)
  let historical = prepareHistoricalRecord(selected.value, view.bestBlock, chain, maximum)
  if historical.error != HistoryError.None:
    return DiskChainResult[DiskPublicationContext](status: DiskChainError.HistoryFailure,
        historyReason: historical.error)
  let overhead = if historical.value.ready: uint64(HistoricalContextPrefixBytes) else: 0'u64
  if uint64(maximum) <= overhead:
    return DiskChainResult[DiskPublicationContext](status: DiskChainError.ContextFailure,
        contextReason: DiskHistoryError.LimitExceeded)
  let context = encodeDiskHistory(target.value, chain,
    RepositoryGeneration(uint64(generation.value)+1), ByteLimit(uint64(maximum)-overhead))
  if context.error != DiskHistoryError.None:
    return DiskChainResult[DiskPublicationContext](status: DiskChainError.ContextFailure,
        contextReason: context.error)
  var bytes = context.value
  if historical.value.ready:
    let wrapped = encodeHistoricalContext(historical.value.nextCursor, bytes, maximum)
    if wrapped.error != HistoryError.None:
      return DiskChainResult[DiskPublicationContext](status: DiskChainError.HistoryFailure,
          historyReason: wrapped.error)
    bytes = wrapped.value
  let next = RepositoryGeneration(uint64(generation.value)+1)
  var history: seq[StateStoreSnapshot] = @[]
  if disk.pagedStorage:
    # Capture the exact target view's retained complete maps before handing its immutable graph to the excluded worker.
    let roots = diskSources(target.value)
    if roots.error != DiskChainError.None:
      return DiskChainResult[DiskPublicationContext](status: DiskChainError.CanonicalMismatch)
    let sources = roots.value
    for index in 0..<sources.len-1: history.add(sources[
        index]) # Do not count the separately supplied current snapshot twice.
  let captured = DiskPublicationContext(bytes: bytes, previous: selected.value,
    history: history, historical: historical.value, next: next)
  DiskChainResult[DiskPublicationContext](status: DiskChainError.None, completed: captured)
func ready*(publication: PreparedDiskPublication): bool =
  ## Defaults never authorize worker publication or canonical update access.
  publication.initialized
func chainUpdate*(publication: PreparedDiskPublication): PreparedChainUpdate {.requires:
    publication.initialized.} =
  ## Retain the original opaque update for host installation after a confirmed durable receipt.
  publication.update
proc prepareDiskPublication*(disk: DiskStateStore, owner: ApplicationChain,
    prepared: PreparedChainUpdate, chain: StorageChainId,
    limit: ByteLimit, replay = false): DiskChainResult[PreparedDiskPublication] =
  ## Stage bounded context without journal mutation; caller must also preflight enabled RPC and hold exclusion.
  if not owner.canInstallPrepared(prepared):
    return DiskChainResult[PreparedDiskPublication](status: DiskChainError.CanonicalMismatch)
  let context = prepareContextView(disk, owner, prepared.chainView, chain, limit)
  if context.error != DiskChainError.None:
    case context.error
    of DiskChainError.HistoryFailure:
      return DiskChainResult[PreparedDiskPublication](status: DiskChainError.HistoryFailure,
          historyReason: context.historyError)
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
      update: prepared, context: context.value.bytes, previous: context.value.previous,
      history: context.value.history, historical: context.value.historical, replay: replay,
      next: context.value.next))
proc commitDiskPublication*(disk: var DiskStateStore,
    publication: PreparedDiskPublication): DiskChainResult[RepositoryGeneration] =
  ## Perform synchronous IO only under exclusive ownership; this never touches application or RPC objects.
  ## A reused context-only parent still requires the exact expected journal generation.
  if not publication.initialized:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  let selected = disk.snapshotContext
  if selected.error != FileError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.FileFailure,
        fileReason: selected.error)
  if selected.value != publication.previous:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  let generation = disk.generation
  if generation.error != DiskStoreError.None or uint64(generation.value) != uint64(
      publication.next)-1:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  let historical = stagePreparedHistory(disk, publication.historical)
  if historical.error != HistoryError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.HistoryFailure,
        historyReason: historical.error)
  let committed = if publication.replay:
    disk.retryPagedCommit(publication.parent, publication.update.stateSnapshot, publication.context,
        publication.history)
  else:
    disk.commit(publication.parent, publication.update.stateSnapshot, publication.context,
        publication.history) # Default publication never repairs existing forensic data.
  if committed.error != DiskStoreError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.StoreFailure,
        storeReason: committed)
  discard completePreparedHistory(disk, publication.historical,
      historical.value) # Confirmed publication survives cleanup refusal, available through disk.historyCleanupError.
  DiskChainResult[RepositoryGeneration](status: DiskChainError.None, completed: publication.next)
proc stageFailure[T](failed: DiskChainResult[T]): DiskChainResult[
    RepositoryGeneration] =
  ## Propagate only actual guarded preparation refusals without synthesizing missing variant payloads.
  case failed.error
  of DiskChainError.HistoryFailure:
    DiskChainResult[RepositoryGeneration](status: DiskChainError.HistoryFailure,
        historyReason: failed.historyError)
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

func ready*(publication: PreparedCurrentDiskPublication): bool =
  ## A default current publication never carries disk authority.
  publication.data != nil
proc chainUpdate*(publication: PreparedCurrentDiskPublication): PreparedCurrentChainUpdate {.requires: publication.data != nil.} =
  ## The guarded retained update is installed only after a confirmed durable receipt.
  let data = publication.data
  assert data != nil # Retain one stable owner before nullable projection.
  data.update
proc prepareDiskPublication*(disk: DiskStateStore, owner: ApplicationChain,
    prepared: PreparedCurrentChainUpdate, chain: StorageChainId,
    limit: ByteLimit, replay = false): DiskChainResult[PreparedCurrentDiskPublication] =
  ## Stage bounded context without journal mutation; caller must also preflight enabled RPC and hold exclusion.
  if not owner.canInstallPrepared(prepared):
    return DiskChainResult[PreparedCurrentDiskPublication](status: DiskChainError.CanonicalMismatch)
  let context = prepareContextView(disk, owner, prepared.currentUpdateView, chain, limit)
  if context.error != DiskChainError.None:
    case context.error
    of DiskChainError.HistoryFailure:
      return DiskChainResult[PreparedCurrentDiskPublication](status: DiskChainError.HistoryFailure,
          historyReason: context.historyError)
    of DiskChainError.ContextFailure:
      return DiskChainResult[PreparedCurrentDiskPublication](status: DiskChainError.ContextFailure,
        contextReason: context.contextError)
    of DiskChainError.FileFailure:
      return DiskChainResult[PreparedCurrentDiskPublication](status: DiskChainError.FileFailure,
        fileReason: context.fileError)
    of DiskChainError.GenerationOverflow:
      return DiskChainResult[PreparedCurrentDiskPublication](
          status: DiskChainError.GenerationOverflow)
    else:
      return DiskChainResult[PreparedCurrentDiskPublication](
          status: DiskChainError.CanonicalMismatch)
  DiskChainResult[PreparedCurrentDiskPublication](status: DiskChainError.None,
    completed: PreparedCurrentDiskPublication(data: CurrentDiskPublicationData(
      parent: owner.stateSnapshot.value,
      update: prepared, context: context.value.bytes, previous: context.value.previous,
      history: context.value.history, historical: context.value.historical, replay: replay,
      next: context.value.next)))
proc commitDiskPublication*(disk: var DiskStateStore,
    publication: PreparedCurrentDiskPublication): DiskChainResult[RepositoryGeneration] =
  ## Perform synchronous IO only under exclusive ownership; this never touches application or RPC objects.
  ## A reused context-only parent still requires the exact expected journal generation.
  let data = publication.data
  if data == nil:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  let selected = disk.snapshotContext
  if selected.error != FileError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.FileFailure,
        fileReason: selected.error)
  if selected.value != data.previous:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  let generation = disk.generation
  if generation.error != DiskStoreError.None or uint64(generation.value) != uint64(
      data.next)-1:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  let historical = stagePreparedHistory(disk, data.historical)
  if historical.error != HistoryError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.HistoryFailure,
        historyReason: historical.error)
  let committed = if data.replay:
    disk.retryPagedCommit(data.parent, data.update.currentUpdateState, data.context, data.history)
  else:
    disk.commit(data.parent, data.update.currentUpdateState, data.context,
        data.history) # Legacy and current updates retain identical explicit recovery authority.
  if committed.error != DiskStoreError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.StoreFailure,
        storeReason: committed)
  discard completePreparedHistory(disk, data.historical,
      historical.value) # Confirmed publication survives cleanup refusal, available through disk.historyCleanupError.
  DiskChainResult[RepositoryGeneration](status: DiskChainError.None, completed: data.next)

proc publishDiskChain*(disk: var DiskStateStore, owner: var ApplicationChain,
    prepared: PreparedCurrentChainUpdate, chain: StorageChainId,
    limit: ByteLimit): DiskChainResult[RepositoryGeneration] =
  ## Stable exclusive owners span preflight/fsync/install; failure never advances the application.
  let staged = prepareDiskPublication(disk, owner, prepared, chain, limit)
  if staged.error != DiskChainError.None: return stageFailure(staged)
  let committed = commitDiskPublication(disk, staged.value)
  if committed.error != DiskChainError.None: return committed
  owner.installPrepared(prepared) # No execution, capture or typed fallible composition remains after fsync.
  committed
proc publishDiskChain*(disk: var DiskStateStore, owner: var ApplicationChain,
    rpc: var rpc_server.Server, prepared: PreparedCurrentChainUpdate, chain: StorageChainId,
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


proc confirmsCurrentDiskPublication*(disk: DiskStateStore,
    publication: PreparedCurrentDiskPublication, generation: RepositoryGeneration): bool =
  ## After collection/join, bind a claimed confirmed receipt to the exact current candidate, selected generation and full context.
  ## Read only validated cached owners/metadata; callers must not access any leased graph while a worker is active.
  let data = publication.data
  if data == nil or uint64(generation) != uint64(data.next): return false
  let selected = disk.generation
  if selected.error != DiskStoreError.None or uint64(selected.value) != uint64(
      data.next): return false
  let state = disk.snapshot
  if state.error != DiskStoreError.None or not sameStateSnapshot(state.value,
      data.update.currentUpdateState): return false
  let context = disk.snapshotContext
  context.error == FileError.None and context.value == data.context

func ready*(maintenance: PreparedDiskMaintenance): bool =
  ## Default/refused maintenance objects grant neither graph borrowing nor file mutation authority.
  maintenance.initialized
proc prepareDiskMaintenance*(disk: DiskStateStore, owner: ApplicationChain,
    chain: StorageChainId, limit: ByteLimit): DiskChainResult[PreparedDiskMaintenance] =
  ## Capture only the current canonical rolling/finality roots after exact disk/context binding, without IO.
  let current = disk.snapshot
  if current.error != DiskStoreError.None:
    return DiskChainResult[PreparedDiskMaintenance](status: DiskChainError.StoreFailure,
        storeReason: current)
  let canonical = owner.stateSnapshot
  if canonical.error != StateStoreError.None or not sameStateSnapshot(current.value,
      canonical.value):
    return DiskChainResult[PreparedDiskMaintenance](status: DiskChainError.CanonicalMismatch)
  let usage = disk.managedDiskUsage
  if usage.error != FileError.None:
    return DiskChainResult[PreparedDiskMaintenance](status: DiskChainError.FileFailure,
        fileReason: usage.error)
  let previous = disk.snapshotContext
  if previous.error != FileError.None:
    return DiskChainResult[PreparedDiskMaintenance](status: DiskChainError.FileFailure,
        fileReason: previous.error)
  let context = encodeMatchingDiskHistory(owner, chain, usage.value.generation, limit,
      previous.value)
  if context.error != DiskHistoryError.None:
    return DiskChainResult[PreparedDiskMaintenance](status: DiskChainError.ContextFailure,
        contextReason: context.error)
  if previous.value != context.value:
    return DiskChainResult[PreparedDiskMaintenance](status: DiskChainError.CanonicalMismatch)
  let sources = diskSources(owner)
  if sources.error != DiskChainError.None:
    return DiskChainResult[PreparedDiskMaintenance](status: DiskChainError.CanonicalMismatch)
  var roots: seq[StateRoot] = @[]
  for source in sources.value: roots.add(source.commitment.root)
  DiskChainResult[PreparedDiskMaintenance](status: DiskChainError.None,
    completed: PreparedDiskMaintenance(initialized: true, parent: current.value,
      generation: usage.value.generation, epoch: usage.value.epoch, context: context.value, roots: roots))
proc commitDiskMaintenance*(disk: var DiskStateStore,
    maintenance: PreparedDiskMaintenance): DiskChainResult[ManagedCompaction] =
  ## Run only on the excluded storage worker/startup owner; physical replacement never installs a canonical successor.
  if not maintenance.initialized:
    return default(DiskChainResult[ManagedCompaction])
  let current = disk.snapshot
  if current.error != DiskStoreError.None:
    return DiskChainResult[ManagedCompaction](status: DiskChainError.StoreFailure,
        storeReason: current)
  let usage = disk.managedDiskUsage
  if usage.error != FileError.None:
    return DiskChainResult[ManagedCompaction](status: DiskChainError.FileFailure,
        fileReason: usage.error)
  if not sameStateSnapshot(current.value, maintenance.parent) or
      uint64(usage.value.generation) != uint64(maintenance.generation) or
      uint64(usage.value.epoch) != uint64(maintenance.epoch):
    return DiskChainResult[ManagedCompaction](status: DiskChainError.CanonicalMismatch)
  let previous = disk.snapshotContext
  if previous.error != FileError.None:
    return DiskChainResult[ManagedCompaction](status: DiskChainError.FileFailure,
        fileReason: previous.error)
  if previous.value != maintenance.context:
    return DiskChainResult[ManagedCompaction](status: DiskChainError.CanonicalMismatch)
  let compacted = disk.compactDiskStateStore(maintenance.parent, maintenance.roots)
  if compacted.error != DiskStoreError.None:
    return DiskChainResult[ManagedCompaction](status: DiskChainError.MaintenanceFailure,
        maintenanceReason: compacted)
  DiskChainResult[ManagedCompaction](status: DiskChainError.None, completed: compacted.value)

proc migrateDiskChain*(source: DiskStateStore, destination: var DiskStateStore, path: string,
    chain: StorageChainId, owner: ApplicationChain, limits: ManagedLimits): DiskChainResult[
        RepositoryGeneration] =
  ## Preserve exactly the already admitted local legacy history and finality; migration grants no new canonical authority.
  if destination.opened: return DiskChainResult[RepositoryGeneration](status: DiskChainError.Busy)
  let current = source.snapshot
  if current.error != DiskStoreError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.StoreFailure,
        storeReason: current)
  let canonical = owner.stateSnapshot
  if canonical.error != StateStoreError.None or not sameStateSnapshot(current.value,
      canonical.value):
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  let generation = source.generation
  if generation.error != DiskStoreError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.FileFailure,
        fileReason: generation.fileError)
  let previous = source.snapshotContext
  if previous.error != FileError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.FileFailure,
        fileReason: previous.error)
  let context = encodeMatchingDiskHistory(owner, chain, generation.value, limits.contextBytes,
      previous.value)
  if context.error != DiskHistoryError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.ContextFailure,
        contextReason: context.error)
  if previous.value != context.value:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  let captured = diskSources(owner)
  if captured.error != DiskChainError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  var roots: seq[StateRoot] = @[]
  for selected in captured.value: roots.add(selected.commitment.root)
  if hasHistoricalContext(previous.value):
    # Preserve the admitted scalar selection and stream complete records before publishing the destination core.
    let decoded = decodeHistoricalContext(previous.value, chain, limits.contextBytes)
    if decoded.error != HistoryError.None:
      return DiskChainResult[RepositoryGeneration](status: DiskChainError.HistoryFailure,
          historyReason: decoded.error)
    let files = openHistoryFiles(source.databasePath & ".history", chain)
    if files.error != HistoryError.None:
      return DiskChainResult[RepositoryGeneration](status: DiskChainError.HistoryFailure,
          historyReason: files.error)
    let selected = validateHistorySelection(files.value, decoded.value.historicalCursor, DefaultHistoricalRecordBytes)
    if selected.error != HistoryError.None:
      return DiskChainResult[RepositoryGeneration](status: DiskChainError.HistoryFailure,
          historyReason: selected.error)
    let historical = copyHistoricalSelection(selected.value, path & ".history", DefaultHistoricalRecordBytes)
    if historical.error != HistoryError.None:
      return DiskChainResult[RepositoryGeneration](status: DiskChainError.HistoryFailure,
          historyReason: historical.error)
  let copied = migrateDiskStateStore(source, destination, path, chain, roots, limits)
  if copied.error != DiskStoreError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.StoreFailure,
        storeReason: copied)
  DiskChainResult[RepositoryGeneration](status: DiskChainError.None, completed: generation.value)

proc retireHistoryPredecessor(disk: var DiskStateStore): HistoryError =
  ## Context-only paged policy publications obey the same bounded predecessor/pinned-reader retirement contract as blocks.
  if not disk.pagedRetirementPending: return HistoryError.None
  let prepared = disk.preparePagedRetirement
  if prepared.error != DiskStoreError.None: return HistoryError.IoFailure
  let retired = disk.commitPagedRetirement(prepared.value)
  if retired.error == DiskStoreError.FileFailure:
    if retired.fileError == FileError.Busy: return HistoryError.Busy
    if retired.fileError == FileError.PublishedUnsynced: return HistoryError.PublishedUnsynced
  if retired.error != DiskStoreError.None: return HistoryError.IoFailure
  if retired.value.retirementError != FileError.None: return HistoryError.PublishedUnsynced
  HistoryError.None
proc configureDiskHistory*(disk: var DiskStateStore, owner: var ApplicationChain,
    chain: StorageChainId, policy: HistoryPolicy, limit: ByteLimit,
    recordBytes = DefaultHistoricalRecordBytes): DiskChainResult[RepositoryGeneration] =
  ## Startup-only policy migration stages complete history, atomically selects context, then reclaims excluded records.
  let current = disk.snapshot
  let canonical = owner.stateSnapshot
  if current.error != DiskStoreError.None or canonical.error != StateStoreError.None or
      not sameStateSnapshot(current.value, canonical.value):
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  let generation = disk.generation
  if generation.error != DiskStoreError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.HistoryFailure,
        historyReason: HistoryError.IoFailure)
  let previous = disk.snapshotContext
  if previous.error != FileError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.FileFailure,
        fileReason: previous.error)
  let maximum = ByteLimit(min(uint64(limit), uint64(disk.applicationContextLimit)))
  let authority = encodeMatchingDiskHistory(owner, chain, generation.value, maximum, previous.value)
  if authority.error != DiskHistoryError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.ContextFailure,
        contextReason: authority.error)
  if authority.value != previous.value:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  let configured = prepareHistoryConfiguration(disk, owner, chain, policy, previous.value,
    generation.value, maximum, recordBytes)
  if configured.error != HistoryError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.HistoryFailure,
        historyReason: configured.error)
  let prepared = configured.value
  if not prepared.changed:
    discard completeHistorySelection(disk, prepared.cleanupFrom, prepared.selection)
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.None,
        completed: generation.value)
  let nextOwner = prepared.configuredOwner
  let retirement = retireHistoryPredecessor(disk)
  if retirement != HistoryError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.HistoryFailure,
        historyReason: retirement)
  let sources = liveDiskSources(nextOwner)
  if sources.error != HistoryError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.CanonicalMismatch)
  var history: seq[StateStoreSnapshot] = @[]
  if disk.pagedStorage:
    let retained = sources.value
    for index in 0..<retained.len-1: history.add(retained[
        index]) # Keep the exact old live/finality roots during a context-only paged publication.
  let committed = disk.commit(current.value, current.value, prepared.context, history)
  if committed.error != DiskStoreError.None:
    return DiskChainResult[RepositoryGeneration](status: DiskChainError.StoreFailure,
        storeReason: committed)
  owner = nextOwner # Assignment-only live-window replacement follows confirmed canonical context publication.
  discard completeHistorySelection(disk, prepared.cleanupFrom, prepared.selection,
      prepared.reseeded)
  let retired = retireHistoryPredecessor(disk)
  if retired != HistoryError.None:
    disk.recordHistoryCleanup(retired) # A foreign pinned reader is explicit backpressure after the new policy is already selected.
    if retired != HistoryError.Busy:
      return DiskChainResult[RepositoryGeneration](status: DiskChainError.HistoryFailure,
          historyReason: HistoryError.PublishedUnsynced)
  DiskChainResult[RepositoryGeneration](status: DiskChainError.None, completed: prepared.generation)
