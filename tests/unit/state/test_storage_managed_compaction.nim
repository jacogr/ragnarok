# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Atomic managed reclamation retains explicit complete roots and old readers without changing state generation.
import std/assertions
import std/syncio
import ../../support/storage_samples
import ../../support/app_managed_storage_samples
import ../../../src/storage/managed_repository as storage_managed_repository
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie
proc main() {.raises.} =
  ## Drop one historical root, preserve another and continue publishing against the new physical owner.
  let limits = managedStorageLimits()
  var memory = newNodeRepository(limits.repository)
  let first = storageTrie(7)
  let second = storageTrie(8)
  let third = storageTrie(10)
  let initial = memory.publish(memory.snapshot.value, exportFullTrie(first,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(initial, [initial.commitment.root], limits.roots).value
  var repository = default(ManagedRepository)
  defer:
    if repository.opened: discard repository.close
  let path = "storage-managed-compaction"
  assert initializeManagedRepository(repository, path, default(StorageChainId), selection,
    [1'u8], limits, StorageSchema.FullStateV1) == FileError.None
  let old = repository.snapshot.value
  let repeated = repository.snapshot.value
  assert old.matches(repeated) and repeated.matches(old)
  assert not old.matches(default(RepositoryView)) and not default(RepositoryView).matches(old)
  assert not default(RepositoryView).matches(default(RepositoryView))
  assert array[32, byte](old.commitment.root) == array[32, byte](initial.commitment.root)
  assert uint64(old.generation) == uint64(initial.generation)
  assert not old.matches(initial) # Managed initialization cloned the exact same metadata into a different owner.
  let beforeRefusals = getOccupiedMem()
  for attempt in 0..<1000:
    # Foreign equal-metadata views cannot authorize maintenance, even with otherwise invalid root inventories.
    assert repository.compact(initial, []).error == FileError.StaleView
    assert repository.compact(default(RepositoryView), [old.commitment.root]).error ==
        FileError.StaleView
  assert getOccupiedMem() == beforeRefusals
  assert uint64(repository.physicalEpoch.value) == 1 and repository.snapshot.value.matches(old)
  let middle = repository.publish(old, exportTrieChanges(first, second,
      limits.repository.codec.records).value, [2'u8]).value
  let head = repository.publish(middle, exportTrieChanges(second, third,
      limits.repository.codec.records).value, [3'u8]).value
  assert not old.matches(head) and not head.matches(old)
  assert repository.compact(old, [head.commitment.root]).error == FileError.StaleView
  assert repository.compact(head, [middle.commitment.root]).error == FileError.InvalidRetention
  let result = repository.compact(head, [middle.commitment.root, head.commitment.root]).value
  assert uint64(result.epoch) == 2 and uint64(result.generation) == 3
  assert result.reclaimedNodes > 0 and result.reclaimedValueBytes > 0
  assert result.cleanup == FileError.None
  let compacted = repository.snapshot.value
  assert uint64(compacted.generation) == uint64(head.generation)
  assert array[32, byte](compacted.commitment.root) == array[32, byte](head.commitment.root)
  assert compacted.storedNodes < head.storedNodes
  assert restoreHistoricalStateEntries(compacted, old.commitment.root,
      limits.repository.codec.trie).error == RepositoryError.MissingNode
  assert restoreHistoricalStateEntries(compacted, middle.commitment.root,
      limits.repository.codec.trie).value.len == 2
  assert restoreHistoricalStateEntries(old, old.commitment.root,
      limits.repository.codec.trie).value.len == 2
  assert repository.snapshotContext.value == @[3'u8]
  assert repository.publish(head, exportTrieChanges(third, third,
      limits.repository.codec.records).value, [4'u8]).batchFailure.error ==
      RepositoryError.StaleView
  let next = repository.publish(compacted, exportTrieChanges(third, third,
      limits.repository.codec.records).value, [4'u8]).value
  assert uint64(next.generation) == 4
  assert repository.close == FileError.None
  assert old.matches(repeated) # Source retirement cannot change an independently retained owner's exact identity.
  assert openManagedRepository(repository, path, default(StorageChainId), limits,
      StorageSchema.FullStateV1) == FileError.None
  assert uint64(repository.physicalEpoch.value) == 2
  assert uint64(repository.snapshot.value.generation) == 4
  assert repository.snapshotContext.value == @[4'u8]
  let repeatedCompaction = repository.compact(repository.snapshot.value, [middle.commitment.root,
      next.commitment.root]).value
  assert uint64(repeatedCompaction.epoch) == 3 and repeatedCompaction.reclaimedNodes == 0
  assert repository.close == FileError.None
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2), ManagedEpoch(3)])
  assert memory.close == RepositoryError.None
try:
  main()
except:
  quit(2)
echo "PASS storage managed compaction: retained roots, reclaimed union, unchanged generation and continued publication"
