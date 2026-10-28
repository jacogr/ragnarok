# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The explicit managed facade preserves physical publication semantics and scalar lifecycle polling.
# @@Verification={"arc":"managed_file_facade_arc_release"}
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/storage_samples
import ../../support/app_managed_storage_samples
import ../../support/testing_arc_evidence
import ../../../src/storage/file_repository as storage_file_repository
import ../../../src/storage/managed_repository as storage_managed_repository
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/storage/durability as storage_durability
import ../../../src/codec/bounded as codec_bounded
proc cycle(path: string, limits: ManagedLimits) =
  ## Composite native ownership retires completely after each independent facade acquisition.
  var file = default(FileRepository)
  assert openManagedFileRepository(file, path, default(StorageChainId), limits,
    StorageSchema.FullStateV1) == FileError.None
  assert uint64(file.snapshot.value.generation) == 2 and file.snapshotContext.value == @[2'u8]
  assert file.close == FileError.None
proc main() {.raises.} =
  ## Ordinary legacy creation remains distinct from explicit managed seed/reopen and unsupported maintenance.
  let limits = managedStorageLimits()
  var memory = newNodeRepository(limits.repository)
  let first = storageTrie(7)
  let second = storageTrie(8)
  let initial = memory.publish(memory.snapshot.value, exportFullTrie(first,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(initial, [initial.commitment.root], limits.roots).value
  var file = default(FileRepository)
  var competitor = default(FileRepository)
  defer:
    if competitor.opened: discard competitor.close
    if file.opened: discard file.close
  let path = "managed-file-facade"
  assert initializeManagedFileRepository(file, path, default(StorageChainId), selection,
    [1'u8], limits, StorageSchema.FullStateV1) == FileError.None
  assert file.opened and file.storageSchema.value == StorageSchema.FullStateV1
  assert openManagedFileRepository(competitor, path, default(StorageChainId), limits,
    StorageSchema.FullStateV1) == FileError.Busy
  let old = file.snapshot.value
  let changes = exportTrieChanges(first, second, limits.repository.codec.records).value
  assert file.publish(initial, changes, [2'u8]).batchFailure.error == RepositoryError.StaleView
  let next = file.publish(old, changes, [2'u8]).value
  assert file.synchronize.value == StorageDurability.FileAndDirectorySynced
  let compacted = file.compact(next, [next.commitment.root]).value
  assert uint64(compacted.epoch) == 2 and compacted.cleanup == FileError.None
  assert file.managedUsage.value.storedNodes < next.storedNodes
  assert file.close == FileError.None and not file.opened
  assert file.close == FileError.Uninitialized
  for iteration in 0..<10: cycle(path, limits)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(path, limits)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("app_managed_file_facade", 1000, before, after)
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
  var legacy = "managed-facade-legacy.wal"
  let policy = JournalLimits(repository: limits.repository, bytes: limits.journalBytes)
  assert initializeFileRepository(file, legacy, default(StorageChainId), policy) == FileError.None
  assert file.managedUsage.error == FileError.UnsupportedLayout
  assert file.compact(file.snapshot.value, []).error == FileError.UnsupportedLayout
  assert file.close == FileError.None
  assert posix.unlink(legacy.toCString()) == 0
  assert memory.close == RepositoryError.None
try:
  main()
except:
  quit(2)
echo "PASS managed file facade: explicit layout, scalar lifecycle, publication, compaction and legacy compatibility"
