# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit-close durable complete-state owner stages private updates before journal publication.
## Ordinary retained StateStore snapshots/forks keep their memory contract after close or IO refusal.

import std/assertions
import ./store
import ../storage/[file_repository, node_repository, node_records, full_state_trie,
  database_identity, durability]
import ../codec/[state_trie, bounded]

type
  DiskStoreError* {.pure.} = enum ## Selected failures expose reasons alone; roots grant no block authority.
    Uninitialized, None, Busy, TrustMismatch, StateFailure, ExportFailure, FileFailure, RepositoryFailure
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
    source: StateStoreSnapshot, limits: JournalLimits): DiskStoreResult[StateStoreSnapshot] =
  ## Create exclusively from an explicit complete seed; failures retire handles but preserve forensic files.
  if store.opened: return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.Busy)
  let candidate = forkStateStore(source)
  if candidate.error != StateStoreError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.StateFailure,
      stateReason: candidate.error)
  let batch = source.exportStateSnapshot(limits.repository.codec.records)
  if batch.error != TrieError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.ExportFailure,
      exportReason: batch.error)
  let initialized = initializeFileRepository(store.journal, path, chain, limits)
  if initialized != FileError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.FileFailure,
      fileReason: initialized)
  let published = store.journal.publish(store.journal.snapshot.value, batch.value)
  if published.error != FileError.None:
    discard store.journal.close # No failed initialization exports a live descriptor owner.
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.FileFailure,
      fileReason: published.error)
  store.state = candidate.value
  store.limits = limits
  DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.None, completed: source)
proc openDiskStateStore*(store: var DiskStateStore, path: string, chain: StorageChainId,
    expectedRoot: StateRoot, expectedGeneration: RepositoryGeneration,
    policy: StateStoreLimits, limits: JournalLimits): DiskStoreResult[StateStoreSnapshot] =
  ## Strictly replay then compare independently supplied authority before constructing writable state.
  if store.opened: return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.Busy)
  let opened = openFileRepository(store.journal, path, chain, limits)
  if opened != FileError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.FileFailure,
        fileReason: opened)
  var adopted = false
  defer:
    if not adopted: discard store.journal.close # Every refused trust/policy/hash check releases its lock.
  let physical = store.journal.snapshot.value
  if uint64(physical.generation) != uint64(expectedGeneration) or
      array[32, byte](physical.commitment.root) != array[32, byte](expectedRoot):
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.TrustMismatch)
  let entries = restoreStateEntries(physical, expectedRoot, policy.trie)
  if entries.error != RepositoryError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.RepositoryFailure,
      repositoryReason: entries.error)
  let candidate = newStateStore(entries.value, policy)
  if candidate.error != StateStoreError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.StateFailure,
      stateReason: candidate.error)
  let restored = candidate.value.snapshot.value
  if array[32, byte](restored.commitment.root) != array[32, byte](expectedRoot):
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.TrustMismatch)
  store.state = candidate.value
  store.limits = limits
  adopted = true
  DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.None, completed: restored)
proc apply*(store: var DiskStateStore,
    writes: openArray[StateWrite]): DiskStoreResult[StateStoreSnapshot] =
  ## Validate/hash a private fork, append and synchronize its delta, then replace the live state once.
  let before = store.snapshot
  if before.error != DiskStoreError.None: return before
  if writes.len == 0: return before # Empty batches preserve identity and never consume a journal generation.
  var candidate = forkStateStore(before.value).value
  let changed = candidate.apply(writes)
  if changed.error != StateStoreError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.StateFailure,
      stateReason: changed.error)
  let batch = exportStateChanges(before.value, changed.value, store.limits.repository.codec.records)
  if batch.error != TrieError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.ExportFailure,
      exportReason: batch.error)
  let published = store.journal.publish(store.journal.snapshot.value, batch.value)
  if published.error != FileError.None:
    return DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.FileFailure,
      fileReason: published.error)
  store.state = candidate # Only a confirmed durable frame authorizes the matching memory snapshot.
  DiskStoreResult[StateStoreSnapshot](status: DiskStoreError.None, completed: changed.value)
proc synchronize*(store: var DiskStateStore): FileResult[StorageDurability] =
  ## A successful receipt confirms file/directory synchronization, never canonical block selection.
  store.journal.synchronize
