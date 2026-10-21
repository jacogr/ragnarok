# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed appends preserve exact parent identity and require explicit exact-prefix torn-tail recovery.
import std/[assertions, syncio]
import ../../support/[storage_samples, managed_storage_samples]
import ../../../src/storage/[managed_repository, managed_manifest, node_repository,
  node_records, full_state_trie, database_identity, file_errors, durability]
import ../../../src/codec/[bounded, state_trie]
proc main() {.raises.} =
  ## Actual file edits exercise torn/corrupt successors without production fault-injection hooks.
  let limits = managedStorageLimits()
  var memory = newNodeRepository(limits.repository)
  let first = storageTrie(7)
  let second = storageTrie(8)
  let initial = memory.publish(memory.snapshot.value, exportFullTrie(first,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(initial, [initial.commitment.root], limits.roots).value
  var repository = default(ManagedRepository)
  defer:
    if repository.opened: discard repository.close
  let path = "storage-managed-append"
  assert initializeManagedRepository(repository, path, default(StorageChainId), selection,
    [1'u8], limits, StorageSchema.FullStateV1) == FileError.None
  let old = repository.snapshot.value
  let changes = exportTrieChanges(first, second, limits.repository.codec.records).value
  assert repository.publish(initial, changes, [2'u8]).batchFailure.error ==
      RepositoryError.StaleView
  let selected = repository.publish(old, changes, [2'u8]).value
  assert uint64(selected.generation) == 2
  assert repository.snapshotContext.value == @[2'u8]
  assert repository.synchronize.value == StorageDurability.FileAndDirectorySynced
  assert repository.close == FileError.None
  assert openManagedRepository(repository, path, default(StorageChainId), limits,
    StorageSchema.FullStateV1) == FileError.None
  assert array[32, byte](repository.snapshot.value.commitment.root) == array[32, byte](
      selected.commitment.root)
  assert repository.snapshotContext.value == @[2'u8]
  assert repository.close == FileError.None
  let journal = path & "/journal-0000000000000001.wal"
  let exact = readFile(journal)
  writeFile(journal, exact & "torn")
  assert openManagedRepository(repository, path, default(StorageChainId), limits,
    StorageSchema.FullStateV1) == FileError.InvalidJournal
  assert recoverManagedRepository(repository, path, default(StorageChainId), limits,
    old.generation, old.commitment.root, StorageSchema.FullStateV1) == FileError.RecoveryMismatch
  assert readFile(journal) == exact & "torn"
  assert recoverManagedRepository(repository, path, default(StorageChainId), limits,
    selected.generation, selected.commitment.root, StorageSchema.FullStateV1) == FileError.None
  assert repository.snapshotContext.value == @[2'u8]
  assert readFile(journal) == exact
  let unchanged = exportTrieChanges(second, second, limits.repository.codec.records).value
  let next = repository.publish(repository.snapshot.value, unchanged, [3'u8]).value
  assert uint64(next.generation) == 3
  assert repository.close == FileError.None
  let complete = readFile(journal)
  assert recoverManagedRepository(repository, path, default(StorageChainId), limits,
    selected.generation, selected.commitment.root, StorageSchema.FullStateV1) ==
        FileError.RecoveryMismatch
  assert readFile(journal) == complete # A complete visible successor cannot be rolled back to an older token.
  var corrupt = complete
  corrupt[corrupt.high] = char(ord(corrupt[corrupt.high]) xor 1)
  writeFile(journal, corrupt)
  assert recoverManagedRepository(repository, path, default(StorageChainId), limits,
    next.generation, next.commitment.root, StorageSchema.FullStateV1) == FileError.InvalidJournal
  assert readFile(journal) == corrupt
  assert restoreStateEntries(old, old.commitment.root, limits.repository.codec.trie).value.len == 2
  removeManagedSample(path, [ManagedEpoch(1)])
  assert memory.close == RepositoryError.None
try:
  main()
except:
  quit(2)
echo "PASS storage managed append recovery: exact parent, durable context, explicit prefix and corrupt-tail refusal"
