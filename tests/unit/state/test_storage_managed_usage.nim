# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Selected-file usage exposes exact bounded maintenance counters; a fixed checked workload records reclamation cost.
# @@Verification={"arc":"storage_managed_usage_arc_release"}
import std/[assertions, syncio, envvars, monotimes, times]
import ../../support/[storage_samples, managed_storage_samples, arc_evidence]
import ../../../src/storage/managed/[repository as managed_repository, manifest as managed_manifest]
import ../../../src/storage/node/[repository as node_repository, records as node_records]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/database_identity
import ../../../src/storage/file/errors as file_errors
import ../../../src/codec/state/trie as state_trie
proc sample(repository: ManagedRepository) =
  ## Scalar usage queries allocate no detached graphs or buffers.
  let usage = repository.usage.value
  assert usage.storedNodes > 0 and usage.snapshotBytes > 0
proc main() {.raises.} =
  ## Fixed 64 changed-root commits retain the last eight revisions plus one explicit older root.
  let limits = managedStorageLimits()
  var memory = newNodeRepository(limits.repository)
  var trie = storageTrie(0)
  let initial = memory.publish(memory.snapshot.value, exportFullTrie(trie,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(initial, [initial.commitment.root], limits.roots).value
  var repository = default(ManagedRepository)
  let path = "storage-managed-usage"
  assert initializeManagedRepository(repository, path, default(StorageChainId), selection,
    [0'u8], limits, StorageSchema.FullStateV1) == FileError.None
  defer:
    if repository.opened: discard repository.close
  var roots: seq[StateRoot] = @[initial.commitment.root]
  for index in 1..64:
    let next = storageTrie(byte(index))
    let changes = exportTrieChanges(trie, next, limits.repository.codec.records).value
    let selected = repository.publish(repository.snapshot.value, changes, [byte(index)]).value
    if index > 56: roots.add(selected.commitment.root) # An explicit bounded retained-root contract drives maintenance.
    trie = next
  for iteration in 0..<10: sample(repository)
  let occupiedBefore = getOccupiedMem()
  for iteration in 0..<1000: sample(repository)
  let occupiedAfter = getOccupiedMem()
  assert occupiedBefore == occupiedAfter
  recordArcRelease("storage_managed_usage", 1000, occupiedBefore, occupiedAfter)
  let before = repository.usage.value
  let started = getMonoTime()
  let compacted = repository.compact(repository.snapshot.value, roots).value
  let elapsed = (getMonoTime()-started).inNanoseconds
  let after = repository.usage.value
  assert compacted.cleanup == FileError.None and compacted.reclaimedNodes > 0
  assert uint64(after.generation) == 65 and uint64(after.epoch) == 2
  assert after.storedNodes < before.storedNodes
  assert after.journalBytes == uint64(ManagedJournalHeaderBytes)
  assert after.snapshotBytes+after.journalBytes < before.snapshotBytes+before.journalBytes
  for root in roots:
    assert restoreHistoricalStateEntries(repository.snapshot.value, root,
        limits.repository.codec.trie).value.len == 2
  let evidence = getEnv("RAGNAROK_TEST_EVIDENCE")
  if evidence.len > 0:
    writeFile(evidence & "/storage_managed_maintenance.json",
      "{\"commits\":64,\"retained_roots\":9,\"before_nodes\":" & $before.storedNodes &
      ",\"after_nodes\":" & $after.storedNodes & ",\"before_snapshot_bytes\":" &
      $before.snapshotBytes &
      ",\"before_journal_bytes\":" & $before.journalBytes & ",\"after_snapshot_bytes\":" &
      $after.snapshotBytes &
      ",\"after_journal_bytes\":" & $after.journalBytes & ",\"compaction_nanoseconds\":" &
      $elapsed & "}\n")
  assert repository.close == FileError.None
  assert openManagedRepository(repository, path, default(StorageChainId), limits,
      StorageSchema.FullStateV1) == FileError.None
  assert repository.usage.value.snapshotBytes == after.snapshotBytes
  assert repository.usage.value.journalBytes == after.journalBytes
  assert uint64(repository.usage.value.generation) == 65
  assert repository.close == FileError.None
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
  assert memory.close == RepositoryError.None
try:
  main()
except:
  quit(2)
echo "PASS storage managed usage: exact selected extents, bounded retention, reclamation evidence and allocation-free queries"
