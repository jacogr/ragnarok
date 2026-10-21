# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Atomic managed reclamation retains explicit complete roots and old readers without changing state generation.
import std/[assertions, syncio]
import ../../support/[storage_samples, managed_storage_samples]
import ../../../src/storage/[managed_repository, managed_manifest, node_repository,
  node_records, full_state_trie, database_identity, file_errors]
import ../../../src/codec/[bounded, state_trie]
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
  let middle = repository.publish(old, exportTrieChanges(first, second,
      limits.repository.codec.records).value, [2'u8]).value
  let head = repository.publish(middle, exportTrieChanges(second, third,
      limits.repository.codec.records).value, [3'u8]).value
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
  assert openManagedRepository(repository, path, default(StorageChainId), limits,
      StorageSchema.FullStateV1) == FileError.None
  assert uint64(repository.physicalEpoch.value) == 2
  assert uint64(repository.snapshot.value.generation) == 4
  assert repository.snapshotContext.value == @[4'u8]
  let repeated = repository.compact(repository.snapshot.value, [middle.commitment.root,
      next.commitment.root]).value
  assert uint64(repeated.epoch) == 3 and repeated.reclaimedNodes == 0
  assert repository.close == FileError.None
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2), ManagedEpoch(3)])
  assert memory.close == RepositoryError.None
try:
  main()
except:
  quit(2)
echo "PASS storage managed compaction: retained roots, reclaimed union, unchanged generation and continued publication"
