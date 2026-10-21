# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Historic complete roots reuse retained physical records without selecting another live revision.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/storage_samples
import ../../../src/state/[store, disk_store]
import ../../../src/storage/[file_repository, node_repository, database_identity]
import ../../../src/codec/[state_trie, state_layout, bounded]
proc main() {.raises.} =
  ## Strict restart plus independent root/value witnesses covers old, empty and unknown complete roots.
  var path = "storage-historical-roots.db"
  let limits = JournalLimits(repository: storageLimits(), bytes: ByteLimit(1048576))
  let policy = StateStoreLimits(trie: limits.repository.codec.trie, writes: ElementLimit(4),
      writeValueBytes: ByteLimit(64))
  let seed = newStateStore([StateEntry(key: storageKey(0), value: @[7'u8]),
    StateEntry(key: storageKey(128))], policy).value.snapshot.value
  var disk = default(DiskStateStore)
  defer:
    if disk.opened: discard disk.close # Every failed historical read still retires the current file owner.
  var snapshots: seq[StateStoreSnapshot] = @[seed]
  discard initializeDiskStateStore(disk, path, default(StorageChainId), seed, limits).value
  defer: discard posix.unlink(path.toCString())
  for index in 1..4:
    snapshots.add(disk.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Put,
      value: @[byte(index)])]).value)
  let currentRoot = disk.snapshot.value.commitment.root
  assert disk.close == FileError.None
  let current = openDiskStateStore(disk, path, default(StorageChainId), currentRoot,
    RepositoryGeneration(5), policy, limits).value
  for old in snapshots:
    let restored = disk.restoreDiskSnapshot(old.commitment.root, policy).value
    var entries: seq[StateEntry] = @[]
    for index in 0..<old.commitment.entries:
      let key = old.keyAt(StateEntryIndex(index)).value
      assert restored.lookup(key).value.bytes == old.lookup(key).value.bytes
      entries.add(StateEntry(key: key, value: restored.lookup(key).value.bytes))
    let independent = stateTrieRoot(entries, policy.trie).value
    assert array[32, byte](independent.root) == array[32, byte](old.commitment.root)
    assert sameStateSnapshot(current, disk.snapshot.value) and uint64(disk.generation.value) == 5
  var unknown = default(array[32, byte])
  unknown[0] = 42
  assert disk.restoreDiskSnapshot(StateRoot(unknown), policy).repositoryError ==
      RepositoryError.MissingNode
  let empty = disk.restoreDiskSnapshot(default(StateRoot), policy).value
  assert empty.commitment.entries == 0 and empty.commitment.nodes == 0
  var narrow = policy
  narrow.trie.items = ElementLimit(1)
  assert disk.restoreDiskSnapshot(seed.commitment.root, narrow).repositoryError ==
      RepositoryError.LimitExceeded
  assert sameStateSnapshot(current, disk.snapshot.value) and uint64(disk.generation.value) == 5
  assert disk.close == FileError.None
  assert snapshots[0].lookup(storageKey(0)).value.bytes == @[7'u8]
  var physical = default(FileRepository)
  assert openFileRepository(physical, path, default(StorageChainId), limits) == FileError.None
  let view = physical.snapshot.value
  var extracted = restoreHistoricalStateEntries(view, seed.commitment.root, policy.trie).value
  assert extracted.len == 2
  assert array[31, byte](extracted[0].key) == array[31, byte](storageKey(0))
  assert array[31, byte](extracted[1].key) == array[31, byte](storageKey(128))
  extracted[0].value[0] = 99
  assert restoreHistoricalStateEntries(view, seed.commitment.root, policy.trie).value[0].value == @[7'u8]
  assert restoreHistoricalStateEntries(view, default(StateRoot), policy.trie).value.len == 0
  var noNodes = policy.trie
  noNodes.nodes = TrieNodeLimit(0)
  assert restoreHistoricalStateEntries(view, seed.commitment.root, noNodes).error ==
      RepositoryError.LimitExceeded
  assert physical.close == FileError.None
  assert restoreHistoricalStateEntries(view, seed.commitment.root, policy.trie).value[0].value == @[7'u8]
try:
  main()
except:
  quit(2) # Fixture IO failure cannot count as successful historical state restoration.
echo "PASS storage historical roots: trusted complete maps, retained values and unchanged durable selection"
