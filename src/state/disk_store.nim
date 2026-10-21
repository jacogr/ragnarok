# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit-close durable complete-state owner stages private updates before journal publication.
## Ordinary retained StateStore snapshots/forks keep their memory contract after close or IO refusal.

import std/assertions
import ./store
import ../storage/[file_repository, node_repository, node_records, full_state_trie,
  database_identity, durability, managed_repository]
import ../codec/[state_trie, bounded]

type
  DiskStoreError* {.pure.} = enum ## Selected failures expose reasons alone; roots grant no block authority.
    Uninitialized, None, Busy, TrustMismatch, StaleSnapshot, PolicyMismatch, ContextRequired,
    StateFailure, ExportFailure, FileFailure, RepositoryFailure
  DiskStoreResult*[T] = object ## Guard every selected stage before extracting a success or nested reason.
    case status: DiskStoreError
    of None: completed: T
    of StateFailure: stateReason: StateStoreError
    of ExportFailure: exportReason: TrieError
    of FileFailure: fileReason: FileError
    of RepositoryFailure: repositoryReason: RepositoryError
    else: discard # Default, lifecycle and trust failures contain no partial owner.
  DiskStateStore* = object ## A single noncopyable journal owner publishes ordinary immutable state views.
    journal: FileRepository
    state: StateStore
    limits: JournalLimits
    schema: StorageSchema

proc `=copy`*(destination: var DiskStateStore, source: DiskStateStore) {.error.}
  ## The composite owner may never duplicate the journal descriptor or its retirement obligation.
proc `=dup`*(source: DiskStateStore): DiskStateStore {.error.}
  ## Actual lowering must refuse implicit duplication, including non-last-use sink calls.
proc `=destroy`*(store: DiskStateStore) =
  ## FileRepository enforces explicit native retirement before managed state owners are released.
  `=destroy`(store.journal)
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
func opened*(store: DiskStateStore): bool =
  ## Poisoned owners remain opened until the caller explicitly retires their native resources.
  store.journal.opened
proc close*(store: var DiskStateStore): FileError =
  ## Retire the exclusive lock exactly once; independently held memory snapshots remain readable.
  let reason = store.journal.close
  store.state = default(StateStore)
  store.limits = default(JournalLimits)
  reason
proc snapshot*(store: DiskStateStore): DiskStoreResult[StateStoreSnapshot] =
  ## Refuse fresh reads after uncertain IO while already retained views keep their immutable bytes.
  if not store.opened: return default(DiskStoreResult[StateStoreSnapshot])
  let physical = store.journal.snapshot
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
proc snapshotContext*(store: DiskStateStore): FileResult[seq[byte]] =
  ## Return independently owned metadata selected by the same durable generation as the state view.
  store.journal.snapshotContext
proc commit*(store: var DiskStateStore, expected, target: StateStoreSnapshot,
    context: openArray[byte] = []): DiskStoreResult[StateStoreSnapshot] =
  ## Publish a privately prepared immutable snapshot without repeating application or commitment work.
  let before = store.snapshot
  if before.error != DiskStoreError.None: return before
  if not sameStateSnapshot(before.value, expected):
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.StaleSnapshot)
  if not sameStateStorePolicy(expected, target):
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.PolicyMismatch)
  if store.schema == StorageSchema.FullStateV1 and context.len == 0:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.ContextRequired)
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
proc synchronize*(store: var DiskStateStore): FileResult[StorageDurability] =
  ## A successful receipt confirms file/directory synchronization, never canonical block selection.
  store.journal.synchronize

proc restoreDiskSnapshot*(store: DiskStateStore, expected: StateRoot,
    policy: StateStoreLimits): DiskStoreResult[StateStoreSnapshot] =
  ## Reconstruct an explicitly bound historical complete map without changing live selection or generation.
  if not store.opened: return default(DiskStoreResult[StateStoreSnapshot])
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
    context: openArray[byte] = []): DiskStoreResult[StateStoreSnapshot] =
  ## Build the complete generation-one seed before managed creation; no durable empty bootstrap state exists.
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
  var seed = newNodeRepository(limits.repository)
  defer: discard seed.close
  let prepared = seed.publish(seed.snapshot.value, batch.value)
  if prepared.error != RepositoryError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.RepositoryFailure,
        repositoryReason: prepared.error)
  let selection = selectRepositoryRoots(prepared.value, [prepared.value.commitment.root], limits.roots)
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
proc managedDiskUsage*(store: DiskStateStore): FileResult[ManagedUsage] =
  ## Expose bounded selected-file counters without choosing maintenance scheduling or root authority.
  store.journal.managedUsage
