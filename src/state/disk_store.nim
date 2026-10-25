# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit-close durable complete-state owner stages private updates before atomic publication.
## Ordinary retained StateStore snapshots/forks keep their memory contract after close or IO refusal.

import std/assertions
import ./[store, paged_state]
import ../storage/[file_repository, node_repository, node_records, full_state_trie,
  database_identity, durability, managed_repository, file_migration, managed_manifest,
  full_paged_store, full_paged_codec]
import ../codec/[state_trie, bounded]

type
  DiskStoreError* {.pure.} = enum ## Selected failures expose reasons alone; roots grant no block authority.
    Uninitialized, None, Busy, TrustMismatch, StaleSnapshot, PolicyMismatch, ContextRequired,
    StateFailure, ExportFailure, FileFailure, RepositoryFailure, NativeFailure, PagedFailure, GenerationOverflow
  DiskStoreResult*[T] = object ## Guard every selected stage before extracting a success or nested reason.
    case status: DiskStoreError
    of None: completed: T
    of StateFailure: stateReason: StateStoreError
    of ExportFailure: exportReason: TrieError
    of FileFailure: fileReason: FileError
    of RepositoryFailure: repositoryReason: RepositoryError
    of NativeFailure: nativeReason: FullPagedNativeResult[bool]
    of PagedFailure: pagedReason: PagedStateResult[bool]
    else: discard # Default, lifecycle and trust failures contain no partial owner.
  DiskIoResult*[T] = object ## Facade context and synchronization share exact file reasons across distinct physical backends.
    case status: FileError
    of None: completed: T
    else: discard # Failed metadata/durability operations grant no transport or receipt.
  DiskStateStore* = object ## One noncopyable selected backend publishes ordinary immutable complete-state views.
    journal: FileRepository
    paged: FullPagedWriter
    pagedMode: bool
    pagedConfig: FullPagedNativeConfig
    pagedTransport: PagedStateLimits
    state: StateStore
    limits: JournalLimits
    schema: StorageSchema

proc `=copy`*(destination: var DiskStateStore, source: DiskStateStore) {.error.}
  ## The composite owner may never duplicate either native backend or its retirement obligation.
proc `=dup`*(source: DiskStateStore): DiskStateStore {.error.}
  ## Actual lowering must refuse implicit duplication, including non-last-use sink calls.
proc `=destroy`*(store: DiskStateStore) =
  ## Both native backends enforce explicit retirement before resident state owners are released.
  `=destroy`(store.journal)
  `=destroy`(store.paged)
  `=destroy`(store.state)

func error*[T](outcome: DiskStoreResult[T]): DiskStoreError =
  ## Inspect success without granting access to another variant's payload.
  outcome.status
func value*[T](outcome: DiskStoreResult[T]): T {.inline,
    requires: outcome.status == DiskStoreError.None.} =
  ## Only a fully published or independently trusted restored state can escape.
  outcome.completed
func stateError*[T](outcome: DiskStoreResult[T]): StateStoreError {.requires:
    outcome.status == DiskStoreError.StateFailure.} =
  ## Preserve actual StateStore validation, policy and required-hash failures.
  outcome.stateReason
func exportError*[T](outcome: DiskStoreResult[T]): TrieError {.requires:
    outcome.status == DiskStoreError.ExportFailure.} =
  ## Inspect only a refused bounded detached export.
  outcome.exportReason
func fileError*[T](outcome: DiskStoreResult[T]): FileError {.requires:
    outcome.status == DiskStoreError.FileFailure.} =
  ## Preserve uncertain append and lifecycle errors without flattening them to missing data.
  outcome.fileReason
func repositoryError*[T](outcome: DiskStoreResult[T]): RepositoryError {.requires:
    outcome.status == DiskStoreError.RepositoryFailure.} =
  ## Inspect only actual trusted-leaf restoration failures.
  outcome.repositoryReason
func error*[T](outcome: DiskIoResult[T]): FileError =
  ## Context and durability consumers inspect the same native file error domain for every layout.
  outcome.status
func value*[T](outcome: DiskIoResult[T]): T {.inline, requires: outcome.status == FileError.None.} =
  ## No failed/default result grants context bytes or a synchronization receipt.
  outcome.completed
func nativeFailure*[T](outcome: DiskStoreResult[T]): FullPagedNativeResult[bool] {.requires:
    outcome.status == DiskStoreError.NativeFailure.} =
  ## Preserve exact native graph, codec, construction or lifecycle causes behind a selected failure.
  outcome.nativeReason
func pagedFailure*[T](outcome: DiskStoreResult[T]): PagedStateResult[bool] {.requires:
    outcome.status == DiskStoreError.PagedFailure.} =
  ## Bounded complete-map staging failures retain their original state/export/geometry causes.
  outcome.pagedReason
func nativeFailed[T, U](outcome: FullPagedNativeResult[U]): DiskStoreResult[T] {.requires:
    outcome.error != FullPagedNativeError.None.} =
  ## Actual file failures keep the existing startup/recovery domain; other native stages remain distinguishable.
  if outcome.error == FullPagedNativeError.FileFailure:
    DiskStoreResult[T](status: DiskStoreError.FileFailure, fileReason: outcome.fileError)
  else:
    DiskStoreResult[T](status: DiskStoreError.NativeFailure, nativeReason: outcome.failure)
func pagedFailed[T, U](outcome: PagedStateResult[U]): DiskStoreResult[T] {.requires:
    outcome.error != PagedStateError.None.} =
  ## Native failures preserve the facade's exact IO uncertainty domain; private staging grants no prefix.
  if outcome.error == PagedStateError.NativeFailure: nativeFailed[T, bool](outcome.nativeFailure)
  else: DiskStoreResult[T](status: DiskStoreError.PagedFailure, pagedReason: outcome.failure)
func opened*(store: DiskStateStore): bool =
  ## Poisoned owners remain opened until the caller explicitly retires their native resources.
  store.journal.opened or store.paged.opened
proc close*(store: var DiskStateStore): FileError =
  ## Retire the exclusive lock exactly once; independently held memory snapshots remain readable.
  if not store.opened: return FileError.Uninitialized # Preserve the existing closed-owner refusal.
  var reason = FileError.None
  if store.journal.opened: reason = store.journal.close # Retire only an actually acquired journal owner.
  if store.paged.opened:
    let paged = store.paged.close # Always retire the acquired paged owner, even after an independent failure.
    if reason == FileError.None: reason = paged
  store.pagedMode = false
  store.pagedConfig = default(FullPagedNativeConfig)
  store.pagedTransport = default(PagedStateLimits)
  store.state = default(StateStore)
  store.limits = default(JournalLimits)
  reason
proc snapshot*(store: DiskStateStore): DiskStoreResult[StateStoreSnapshot] =
  ## Refuse fresh reads after uncertain IO while already retained views keep their immutable bytes.
  if not store.opened: return default(DiskStoreResult[StateStoreSnapshot])
  if store.pagedMode:
    # Native selected metadata checks the exact CURRENT, immutable inode, lease and uncertainty latch.
    let selected = store.paged.selected
    if selected.error != FullPagedNativeError.None: return nativeFailed[StateStoreSnapshot,
        FullPagedManifest](selected)
  else:
    let physical = store.journal.snapshot # Existing journal and managed owners keep their complete read contract.
    if physical.error != FileError.None:
      return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.FileFailure,
          fileReason: physical.error)
  let current = store.state.snapshot
  if current.error != StateStoreError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.StateFailure,
      stateReason: current.error)
  DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.None, completed: current.value)
proc generation*(store: DiskStateStore): DiskStoreResult[RepositoryGeneration] =
  ## Return a local ordinal only after the journal confirms a usable published owner.
  if not store.opened: return default(DiskStoreResult[RepositoryGeneration])
  if store.pagedMode:
    # Native ordinary generation starts at zero; the contextual application facade starts at one.
    let selected = store.paged.selected
    if selected.error != FullPagedNativeError.None: return nativeFailed[RepositoryGeneration,
        FullPagedManifest](selected)
    let number = uint64(selected.value.generation)
    if number == high(uint64): return DiskStoreResult[RepositoryGeneration](
        status: DiskStoreError.GenerationOverflow)
    return DiskStoreResult[RepositoryGeneration](status: DiskStoreError.None,
        completed: RepositoryGeneration(number+1))
  let current = store.journal.snapshot
  if current.error != FileError.None:
    return DiskStoreResult[RepositoryGeneration](status: DiskStoreError.FileFailure,
      fileReason: current.error)
  DiskStoreResult[RepositoryGeneration](status: DiskStoreError.None,
    completed: current.value.generation)
proc initializeDiskStateStore*(store: var DiskStateStore, path: string, chain: StorageChainId,
    source: StateStoreSnapshot, limits: JournalLimits,
    schema = StorageSchema.FullNodesV1, context: openArray[byte] = []): DiskStoreResult[
        StateStoreSnapshot] =
  ## Create exclusively from an explicit complete seed; failures retire handles but preserve forensic files.
  if store.opened: return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.Busy)
  if schema == StorageSchema.FullStateV1 and context.len == 0:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.ContextRequired)
  let candidate = forkStateStore(source)
  if candidate.error != StateStoreError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.StateFailure,
      stateReason: candidate.error)
  let batch = source.exportStateSnapshot(limits.repository.codec.records)
  if batch.error != TrieError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.ExportFailure,
      exportReason: batch.error)
  let initialized = initializeFileRepository(store.journal, path, chain, limits, schema)
  if initialized != FileError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.FileFailure,
      fileReason: initialized)
  let published = store.journal.publish(store.journal.snapshot.value, batch.value, context)
  if published.error != FileError.None:
    discard store.journal.close # No failed initialization exports a live descriptor owner.
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.FileFailure,
      fileReason: published.error)
  store.state = candidate.value
  store.limits = limits
  store.schema = schema
  DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.None, completed: source)
proc acquireDiskStateStore(store: var DiskStateStore, path: string, chain: StorageChainId,
    expectedRoot: StateRoot, expectedGeneration: RepositoryGeneration,
    policy: StateStoreLimits, limits: JournalLimits, repair: bool,
    schema: StorageSchema, local: bool, managed = false,
    managedLimits = default(ManagedLimits)): DiskStoreResult[
        StateStoreSnapshot] =
  ## Strictly replay then compare independently supplied authority before constructing writable state.
  if store.opened: return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.Busy)
  let opened = if managed:
    if repair:
      recoverManagedFileRepository(store.journal, path, chain, managedLimits, expectedGeneration,
          expectedRoot, schema)
    else:
      openManagedFileRepository(store.journal, path, chain, managedLimits, schema)
  elif repair:
    recoverFileRepository(store.journal, path, chain, limits, expectedGeneration, expectedRoot, schema)
  else:
    openFileRepository(store.journal, path, chain, limits,
        schema) # Ordinary open never mutates an incomplete tail; layout is explicitly selected.
  if opened != FileError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.FileFailure,
        fileReason: opened)
  var adopted = false
  defer:
    if not adopted: discard store.journal.close # Every refused trust/policy/hash check releases its lock.
  let physical = store.journal.snapshot.value
  if not local and (uint64(physical.generation) != uint64(expectedGeneration) or
      array[32, byte](physical.commitment.root) != array[32, byte](expectedRoot)):
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.TrustMismatch)
  if schema == StorageSchema.FullStateV1 and store.journal.snapshotContext.value.len == 0:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.ContextRequired)
  let selectedRoot = if local: physical.commitment.root else: expectedRoot
  let entries = restoreStateEntries(physical, selectedRoot, policy.trie)
  if entries.error != RepositoryError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.RepositoryFailure,
      repositoryReason: entries.error)
  let candidate = newStateStore(entries.value, policy)
  if candidate.error != StateStoreError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.StateFailure,
      stateReason: candidate.error)
  let restored = candidate.value.snapshot.value
  if array[32, byte](restored.commitment.root) != array[32, byte](selectedRoot):
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.TrustMismatch)
  store.state = candidate.value
  store.limits = limits
  store.schema = schema
  adopted = true
  DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.None, completed: restored)
proc openDiskStateStore*(store: var DiskStateStore, path: string, chain: StorageChainId,
    expectedRoot: StateRoot, expectedGeneration: RepositoryGeneration,
    policy: StateStoreLimits, limits: JournalLimits,
    schema = StorageSchema.FullNodesV1): DiskStoreResult[StateStoreSnapshot] =
  ## Read strictly without repair; independently supplied root/generation choose the only admissible head.
  acquireDiskStateStore(store, path, chain, expectedRoot, expectedGeneration, policy, limits, false,
      schema, false)
proc recoverDiskStateStore*(store: var DiskStateStore, path: string, chain: StorageChainId,
    expectedRoot: StateRoot, expectedGeneration: RepositoryGeneration,
    policy: StateStoreLimits, limits: JournalLimits,
    schema = StorageSchema.FullNodesV1): DiskStoreResult[StateStoreSnapshot] =
  ## Explicitly truncate only a plausible incomplete final frame after exact trusted-prefix validation.
  ## Complete successors and complete corrupt frames are never discarded; later restore failure may
  ## leave the authorized repair durable even though no writable StateStore has been adopted.
  acquireDiskStateStore(store, path, chain, expectedRoot, expectedGeneration, policy, limits, true,
      schema, false)

proc openLocalDiskStateStore*(store: var DiskStateStore, path: string, chain: StorageChainId,
    policy: StateStoreLimits, limits: JournalLimits): DiskStoreResult[StateStoreSnapshot] =
  ## Resume only the contextual local database after strict chain/format/graph integrity checks.
  ## The application must additionally bind selected context to its configured profile and restored map.
  acquireDiskStateStore(store, path, chain, default(StateRoot), RepositoryGeneration(0),
    policy, limits, false, StorageSchema.FullStateV1, true)
proc snapshotContext*(store: DiskStateStore): DiskIoResult[seq[byte]] =
  ## Return detached opaque metadata selected by the exact same durable generation as the complete map.
  if store.pagedMode:
    let captured = store.paged.readContext(store.pagedConfig.limits.work)
    if captured.error == FullPagedNativeError.FileFailure:
      return DiskIoResult[seq[byte]](status: captured.fileError) # Preserve native IO uncertainty exactly.
    if captured.error != FullPagedNativeError.None: return DiskIoResult[seq[byte]](
        status: FileError.BackendFailure)
    return DiskIoResult[seq[byte]](status: FileError.None, completed: captured.value.bytes)
  let captured = store.journal.snapshotContext
  if captured.error != FileError.None: return DiskIoResult[seq[byte]](status: captured.error)
  DiskIoResult[seq[byte]](status: FileError.None, completed: captured.value)
proc commit*(store: var DiskStateStore, expected, target: StateStoreSnapshot,
    context: openArray[byte] = [], history: openArray[StateStoreSnapshot] = []): DiskStoreResult[
        StateStoreSnapshot] =
  ## Publish a privately prepared immutable snapshot without repeating application or commitment work.
  let before = store.snapshot
  if before.error != DiskStoreError.None: return before
  if not sameStateSnapshot(before.value, expected):
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.StaleSnapshot)
  if not sameStateStorePolicy(expected, target):
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.PolicyMismatch)
  if store.schema == StorageSchema.FullStateV1 and context.len == 0:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.ContextRequired)
  if store.pagedMode:
    # Keep the exact already prepared immutable memory owner private until both native barriers and retirement succeed.
    let selected = store.paged.selected
    if selected.error != FullPagedNativeError.None: return nativeFailed[StateStoreSnapshot,
        FullPagedManifest](selected)
    if uint64(selected.value.generation) >= high(uint64)-1:
      return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.GenerationOverflow)
    let transport = preparePagedState(target, history, store.pagedTransport)
    if transport.error != PagedStateError.None: return pagedFailed[StateStoreSnapshot,
        PreparedPagedState](transport)
    let retained = forkStateStore(target).value
    var candidate = default(FullPagedCandidate)
    defer:
      if candidate.opened:
        let retired = candidate.close # Failed authoring leaves forensic bytes but never a leaked descriptor.
        if retired != FileError.None: result = DiskStoreResult[StateStoreSnapshot](
            status: DiskStoreError.FileFailure, fileReason: retired)
    let authored = preparePagedStateReplacement(store.paged, candidate, selected.value,
        transport.value, context)
    if authored.error != PagedStateError.None: return pagedFailed[StateStoreSnapshot,
        StorageDurability](authored)
    let published = store.paged.publish(candidate)
    if published.error != FullPagedNativeError.None: return nativeFailed[StateStoreSnapshot,
        FullPagedPublication](published)
    if published.value.retirementError != FileError.None:
      return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.FileFailure,
          fileReason: published.value.retirementError)
    if not published.value.writerUsable: return DiskStoreResult[StateStoreSnapshot](
        status: DiskStoreError.FileFailure, fileReason: FileError.RecoveryRequired)
    store.state = retained
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.None, completed: target)
  let candidate = forkStateStore(target).value
  let batch = exportStateChanges(expected, target, store.limits.repository.codec.records)
  if batch.error != TrieError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.ExportFailure,
      exportReason: batch.error)
  let published = store.journal.publish(store.journal.snapshot.value, batch.value, context)
  if published.error != FileError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.FileFailure,
      fileReason: published.error)
  store.state = candidate # Only a confirmed durable frame authorizes the exact prepared memory owner.
  DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.None, completed: target)
proc apply*(store: var DiskStateStore,
    writes: openArray[StateWrite]): DiskStoreResult[StateStoreSnapshot] =
  ## Ordinary node-only updates stage privately; contextual applications must supply prepared head context.
  let before = store.snapshot
  if before.error != DiskStoreError.None: return before
  if writes.len == 0: return before # Empty batches preserve identity and never consume a journal generation.
  if store.schema == StorageSchema.FullStateV1:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.ContextRequired)
  var candidate = forkStateStore(before.value).value
  let changed = candidate.apply(writes)
  if changed.error != StateStoreError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.StateFailure,
      stateReason: changed.error)
  store.commit(before.value, changed.value)
proc synchronize*(store: var DiskStateStore): DiskIoResult[StorageDurability] =
  ## Confirm fresh file/directory barriers without granting any additional canonical block authority.
  if store.pagedMode:
    let synced = store.paged.synchronize
    if synced.error == FullPagedNativeError.FileFailure: return DiskIoResult[StorageDurability](
        status: synced.fileError)
    if synced.error != FullPagedNativeError.None: return DiskIoResult[StorageDurability](
        status: FileError.RecoveryRequired)
    return DiskIoResult[StorageDurability](status: FileError.None, completed: synced.value)
  let synced = store.journal.synchronize
  if synced.error != FileError.None: return DiskIoResult[StorageDurability](status: synced.error)
  DiskIoResult[StorageDurability](status: FileError.None, completed: synced.value)

proc restoreDiskSnapshot*(store: DiskStateStore, expected: StateRoot,
    policy: StateStoreLimits): DiskStoreResult[StateStoreSnapshot] =
  ## Reconstruct an explicitly bound historical complete map without changing live selection or generation.
  if not store.opened: return default(DiskStoreResult[StateStoreSnapshot])
  if store.pagedMode:
    # Exact live selection must remain usable before historical complete-map reconstruction begins.
    let before = store.snapshot
    if before.error != DiskStoreError.None: return before
    # Complete native traversal and independent map recomputation preserve historical full-state provenance.
    let restored = restorePagedStateStore(store.paged, expected, policy)
    if restored.error != PagedStateError.None: return pagedFailed[StateStoreSnapshot, StateStore](restored)
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.None,
        completed: restored.value.snapshot.value)
  let physical = store.journal.snapshot
  if physical.error != FileError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.FileFailure,
      fileReason: physical.error)
  let entries = restoreHistoricalStateEntries(physical.value, expected, policy.trie)
  if entries.error != RepositoryError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.RepositoryFailure,
      repositoryReason: entries.error)
  let state = newStateStore(entries.value, policy)
  if state.error != StateStoreError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.StateFailure,
      stateReason: state.error)
  let restored = state.value.snapshot.value
  if array[32, byte](restored.commitment.root) != array[32, byte](expected):
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.TrustMismatch)
  DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.None, completed: restored)

proc journalPolicy(limits: ManagedLimits): JournalLimits =
  ## Ordinary commit budgets stay identical when a managed layout owns the physical files.
  JournalLimits(repository: limits.repository, bytes: limits.journalBytes,
      contextBytes: limits.contextBytes)
proc initializeManagedDiskStateStore*(store: var DiskStateStore, path: string,
    chain: StorageChainId, source: StateStoreSnapshot, limits: ManagedLimits,
        schema = StorageSchema.FullNodesV1,
    context: openArray[byte] = [], history: openArray[StateStoreSnapshot] = []): DiskStoreResult[
        StateStoreSnapshot] =
  ## Admit bounded older snapshots and the selected seed before IO; no durable intermediate bootstrap head exists.
  if store.opened: return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.Busy)
  if schema == StorageSchema.FullStateV1 and context.len == 0:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.ContextRequired)
  if uint64(history.len) >= uint64(limits.roots):
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.FileFailure,
        fileReason: FileError.LimitExceeded)
  for retained in history:
    if not sameStateStorePolicy(source, retained):
      return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.PolicyMismatch)
  let candidate = forkStateStore(source)
  if candidate.error != StateStoreError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.StateFailure,
        stateReason: candidate.error)
  var seed = newNodeRepository(limits.repository)
  defer: discard seed.close
  var previous = default(StateStoreSnapshot)
  var roots: seq[StateRoot] = @[]
  for index in 0..history.len:
    # The current source is always provisioned last; every prior owner has the same complete-state policy.
    let target = if index < history.len: history[index] else: source
    let batch = if index == 0: target.exportStateSnapshot(limits.repository.codec.records)
      else: exportStateChanges(previous, target, limits.repository.codec.records)
    if batch.error != TrieError.None:
      return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.ExportFailure,
          exportReason: batch.error)
    let prepared = seed.publish(seed.snapshot.value, batch.value)
    if prepared.error != RepositoryError.None:
      return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.RepositoryFailure,
          repositoryReason: prepared.error)
    roots.add(prepared.value.commitment.root)
    previous = target
  let selection = selectRepositoryRoots(seed.snapshot.value, roots, limits.roots)
  if selection.error != RepositoryError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.RepositoryFailure,
        repositoryReason: selection.error)
  let initialized = initializeManagedFileRepository(store.journal, path, chain, selection.value,
    context, limits, schema)
  if initialized != FileError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.FileFailure,
        fileReason: initialized)
  store.state = candidate.value
  store.limits = journalPolicy(limits)
  store.schema = schema
  DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.None, completed: source)
proc openManagedDiskStateStore*(store: var DiskStateStore, path: string, chain: StorageChainId,
    expectedRoot: StateRoot, expectedGeneration: RepositoryGeneration,
    policy: StateStoreLimits, limits: ManagedLimits,
    schema = StorageSchema.FullNodesV1): DiskStoreResult[StateStoreSnapshot] =
  ## An explicitly selected managed layout still requires the supplied exact root/generation authority.
  acquireDiskStateStore(store, path, chain, expectedRoot, expectedGeneration, policy,
    journalPolicy(limits), false, schema, false, true, limits)
proc openLocalManagedDiskStateStore*(store: var DiskStateStore, path: string, chain: StorageChainId,
    policy: StateStoreLimits, limits: ManagedLimits): DiskStoreResult[StateStoreSnapshot] =
  ## Local restart resumes its validated contextual head; application context authentication remains required.
  acquireDiskStateStore(store, path, chain, default(StateRoot), RepositoryGeneration(0), policy,
    journalPolicy(limits), false, StorageSchema.FullStateV1, true, true, limits)
proc recoverManagedDiskStateStore*(store: var DiskStateStore, path: string, chain: StorageChainId,
    expectedRoot: StateRoot, expectedGeneration: RepositoryGeneration,
    policy: StateStoreLimits, limits: ManagedLimits,
    schema = StorageSchema.FullNodesV1): DiskStoreResult[StateStoreSnapshot] =
  ## Recovery remains explicit and cannot discard a complete successor in either physical layout.
  acquireDiskStateStore(store, path, chain, expectedRoot, expectedGeneration, policy,
    journalPolicy(limits), true, schema, false, true, limits)
proc compactDiskStateStore*(store: var DiskStateStore, expected: StateStoreSnapshot,
    roots: openArray[StateRoot]): DiskStoreResult[ManagedCompaction] =
  ## Physical maintenance keeps the exact public state identity and requires explicit retained roots.
  if store.pagedMode: return DiskStoreResult[ManagedCompaction](status: DiskStoreError.FileFailure,
      fileReason: FileError.UnsupportedLayout) # Paged maintenance uses its own authenticated copy/replay contract.
  let before = store.snapshot
  if before.error == DiskStoreError.Uninitialized: return default(DiskStoreResult[ManagedCompaction])
  if before.error == DiskStoreError.FileFailure:
    return DiskStoreResult[ManagedCompaction](status: DiskStoreError.FileFailure,
        fileReason: before.fileError)
  if before.error == DiskStoreError.StateFailure:
    return DiskStoreResult[ManagedCompaction](status: DiskStoreError.StateFailure,
        stateReason: before.stateError)
  if not sameStateSnapshot(before.value, expected):
    return DiskStoreResult[ManagedCompaction](status: DiskStoreError.StaleSnapshot)
  let compacted = store.journal.compact(store.journal.snapshot.value, roots)
  if compacted.error != FileError.None:
    return DiskStoreResult[ManagedCompaction](status: DiskStoreError.FileFailure,
        fileReason: compacted.error)
  DiskStoreResult[ManagedCompaction](status: DiskStoreError.None, completed: compacted.value)
proc managedDiskUsage*(store: DiskStateStore): DiskIoResult[ManagedUsage] =
  ## Managed maintenance counters are unavailable for explicitly selected paged storage.
  if store.pagedMode: return DiskIoResult[ManagedUsage](status: FileError.UnsupportedLayout)
  let usage = store.journal.managedUsage
  if usage.error != FileError.None: return DiskIoResult[ManagedUsage](status: usage.error)
  DiskIoResult[ManagedUsage](status: FileError.None, completed: usage.value)

proc migrateDiskStateStore*(source: DiskStateStore, destination: var DiskStateStore,
    path: string, chain: StorageChainId, roots: openArray[StateRoot],
    limits: ManagedLimits): DiskStoreResult[StateStoreSnapshot] =
  ## Copy an admitted locked legacy owner into an absent managed destination, preserving policy, generation and context.
  if source.pagedMode: return DiskStoreResult[StateStoreSnapshot](
      status: DiskStoreError.FileFailure,

fileReason: FileError.UnsupportedLayout) # No implicit conversion from a contextual paged artifact.
  if destination.opened: return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.Busy)
  let selected = source.snapshot
  if selected.error != DiskStoreError.None: return selected
  let candidate = forkStateStore(selected.value)
  if candidate.error != StateStoreError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.StateFailure,
        stateReason: candidate.error)
  let migrated = migrateFileRepository(source.journal, destination.journal, path, chain, roots, limits)
  if migrated != FileError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.FileFailure,
        fileReason: migrated)
  destination.state = candidate.value
  destination.limits = journalPolicy(limits)
  destination.schema = source.schema
  DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.None, completed: selected.value)

proc cleanupManagedDiskFiles*(store: var DiskStateStore): FileError =
  ## Startup or an excluded IO owner may remove only the immediate successor and predecessor of a checked head.
  if store.pagedMode: return FileError.UnsupportedLayout # Paged cleanup requires explicit independently replayed authority.
  let selected = store.managedDiskUsage
  if selected.error != FileError.None: return selected.error
  let epoch = uint64(selected.value.epoch)
  if epoch < high(uint64):
    let staged = store.journal.discardManagedStaging
    if staged != FileError.None: return staged
  if epoch > 1:
    return store.journal.cleanupRetiredEpoch(ManagedEpoch(epoch-1))
  FileError.None

proc initializePagedDiskStateStore*(store: var DiskStateStore, path: string,
    source: StateStoreSnapshot, config: FullPagedNativeConfig, transport: PagedStateLimits,
    context: openArray[byte], history: openArray[StateStoreSnapshot] = []): DiskStoreResult[
        StateStoreSnapshot] =
  ## Exclusive contextual bootstrap publishes the current complete root, exact retained roots and context in one epoch.
  if store.opened: return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.Busy)
  if context.len == 0 or uint64(config.limits.contextBytes) == 0:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.ContextRequired)
  let prepared = preparePagedState(source, history, transport)
  if prepared.error != PagedStateError.None: return pagedFailed[StateStoreSnapshot,
      PreparedPagedState](prepared)
  let retained = forkStateStore(source)
  if retained.error != StateStoreError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.StateFailure,
        stateReason: retained.error)
  var adopted = false
  defer:
    if not adopted and store.paged.opened:
      let retired = store.paged.close # No failed bootstrap returns a hidden lease or descriptor obligation.
      if retired != FileError.None: result = DiskStoreResult[StateStoreSnapshot](
          status: DiskStoreError.FileFailure, fileReason: retired)
  let initialized = initializePagedStateStore(store.paged, path, config, prepared.value, context)
  if initialized.error != PagedStateError.None: return pagedFailed[StateStoreSnapshot,
      FullPagedPublication](initialized)
  if initialized.value.retirementError != FileError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.FileFailure,
        fileReason: initialized.value.retirementError)
  if not initialized.value.writerUsable:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.FileFailure,
        fileReason: FileError.RecoveryRequired)
  store.state = retained.value
  store.pagedConfig = config
  store.pagedTransport = transport
  store.pagedMode = true
  store.schema = StorageSchema.FullStateV1
  adopted = true
  DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.None, completed: source)
proc openLocalPagedDiskStateStore*(store: var DiskStateStore, path: string,
    chain: StorageChainId, policy: StateStoreLimits, config: FullPagedNativeConfig,
    transport: PagedStateLimits): DiskStoreResult[StateStoreSnapshot] =
  ## Recover only contextual local full state; application profile/header/history binding still precedes canonical adoption.
  if store.opened: return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.Busy)
  if array[32, byte](chain) != array[32, byte](config.chain):
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.TrustMismatch)
  var adopted = false
  defer:
    if not adopted and store.paged.opened:
      let retired = store.paged.close # Failed map restoration cannot retain a usable execution owner.
      if retired != FileError.None: result = DiskStoreResult[StateStoreSnapshot](
          status: DiskStoreError.FileFailure, fileReason: retired)
  let opened = openLocalFullPagedWriter(store.paged, path, chain, config.limits,
      config.construction, config.replayBytes)
  if opened.error != FullPagedNativeError.None: return nativeFailed[StateStoreSnapshot, bool](opened)
  let selected = store.paged.selected
  if selected.error != FullPagedNativeError.None: return nativeFailed[StateStoreSnapshot,
      FullPagedManifest](selected)
  if uint64(selected.value.generation) == high(uint64):
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.GenerationOverflow)
  let restored = restorePagedStateStore(store.paged, selected.value.root, policy)
  if restored.error != PagedStateError.None: return pagedFailed[StateStoreSnapshot, StateStore](restored)
  store.state = restored.value
  store.pagedConfig = config
  store.pagedConfig.root = selected.value.root
  store.pagedTransport = transport
  store.pagedMode = true
  store.schema = StorageSchema.FullStateV1
  adopted = true
  DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.None,
      completed: store.state.snapshot.value)
