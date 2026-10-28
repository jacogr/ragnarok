# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prepared snapshots retain exact owner/policy authority while context and changed nodes commit together.
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/storage_samples
import ../../../src/state/store as state_store
import ../../../src/state/disk_store as state_disk_store
import ../../../src/storage/file_repository as storage_file_repository
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/bounded as codec_bounded
proc run() {.raises.} =
  ## Root-equal foreign parents and policy changes cannot redirect this durable publication owner.
  var path = "disk-prepared-commit.db"
  let limits = JournalLimits(repository: storageLimits(), bytes: ByteLimit(1048576),
      contextBytes: ByteLimit(4))
  let policy = StateStoreLimits(trie: limits.repository.codec.trie, writes: ElementLimit(4),
      writeValueBytes: ByteLimit(64))
  let entries = [StateEntry(key: storageKey(0), value: @[7'u8]), StateEntry(key: storageKey(128))]
  let original = newStateStore(entries, policy).value.snapshot.value
  let foreign = newStateStore(entries, policy).value.snapshot.value
  var disk = default(DiskStateStore)
  defer:
    if disk.opened: discard disk.close # Failure paths never abandon a native journal lock.
  assert initializeDiskStateStore(disk, path, default(StorageChainId), original, limits,
    StorageSchema.FullStateV1).error == DiskStoreError.ContextRequired
  assert not disk.opened
  discard initializeDiskStateStore(disk, path, default(StorageChainId), original, limits,
    StorageSchema.FullStateV1, [1'u8]).value
  defer: discard posix.unlink(path.toCString())
  let before = readFile(path)
  var working = original.forkStateStore.value
  let target = working.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Put, value: @[8'u8])]).value
  assert disk.commit(foreign, target, [2'u8]).error == DiskStoreError.StaleSnapshot
  assert disk.commit(original, target).error == DiskStoreError.ContextRequired
  assert disk.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Delete)]).error ==
      DiskStoreError.ContextRequired
  # Independently change every complete-map/batch ceiling while retaining equal root and values.
  for field in 0..<6:
    var changed = policy
    case field
    of 0: changed.trie.items = ElementLimit(uint64(policy.trie.items)+1)
    of 1: changed.trie.perValue = ByteLimit(uint64(policy.trie.perValue)+1)
    of 2: changed.trie.totalValueBytes = ByteLimit(uint64(policy.trie.totalValueBytes)+1)
    of 3: changed.trie.nodes = TrieNodeLimit(uint64(policy.trie.nodes)+1)
    of 4: changed.writes = ElementLimit(uint64(policy.writes)+1)
    else: changed.writeValueBytes = ByteLimit(uint64(policy.writeValueBytes)+1)
    let alternate = newStateStore(entries, changed).value.snapshot.value
    assert not sameStateStorePolicy(original, alternate)
    assert disk.commit(original, alternate, [2'u8]).error == DiskStoreError.PolicyMismatch
  assert readFile(path) == before and sameStateSnapshot(original, disk.snapshot.value)
  assert disk.commit(original, target, [1'u8, 2, 3, 4, 5]).fileError == FileError.LimitExceeded
  assert readFile(path) == before and disk.snapshotContext.value == @[1'u8]
  let published = disk.commit(original, target, [2'u8]).value
  assert sameStateSnapshot(target, published) and sameStateSnapshot(target, disk.snapshot.value)
  assert disk.snapshotContext.value == @[2'u8] and uint64(disk.generation.value) == 2
  assert disk.commit(original, target, [3'u8]).error == DiskStoreError.StaleSnapshot
  # A new head context may select unchanged state while still consuming its own durable generation.
  assert sameStateSnapshot(target, disk.commit(target, target, [3'u8]).value)
  assert uint64(disk.generation.value) == 3 and disk.close == FileError.None
  let restored = openLocalDiskStateStore(disk, path, default(StorageChainId), policy, limits).value
  assert restored.lookup(storageKey(0)).value.bytes == @[8'u8]
  assert disk.snapshotContext.value == @[3'u8] and uint64(disk.generation.value) == 3
  assert disk.close == FileError.None
  assert original.lookup(storageKey(0)).value.bytes == @[7'u8]
try:
  run()
except:
  quit(2) # Fixture IO failures cannot substitute for successful publication and restart.
echo "PASS disk prepared commit: exact parent, all policy ceilings, atomic context and local restart"
