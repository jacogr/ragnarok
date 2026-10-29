# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed creation admits all bounded local history and separated finality before publishing a single selected epoch.
import std/[assertions, syncio]
import ../../support/[disk_history_context, managed_storage_samples]
import ../../../src/app/chain
import ../../../src/app/disk/history as disk_history
import ../../../src/chain/[genesis, provider]
import ../../../src/state/[store, disk_store]
import ../../../src/storage/file/repository as file_repository
import ../../../src/storage/managed/[repository as managed_repository, manifest as managed_manifest]
import ../../../src/storage/node/[repository as node_repository, records as node_records]
import ../../../src/storage/[record_codec, database_identity]
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie
proc main() {.raises.} =
  ## Structural history fixtures test local full-map ownership; their seals are never execution certificates.
  let fixture = diskHistoryFixture()
  let owner = initApplicationChain(fixture.view).value
  let limits = ManagedLimits(repository: RepositoryLimits(codec: RecordLimits(
    trie: fixture.policy.trie, records: TrieExportLimits(records: TrieNodeLimit(100000),
      valueBytes: ByteLimit(1048576)), encoded: ByteLimit(4194304)), records: ElementLimit(100000),
      valueBytes: ByteLimit(16777216)), roots: ElementLimit(9), snapshotBytes: ByteLimit(33554432),
      journalBytes: ByteLimit(33554432), contextBytes: ByteLimit(1048576))
  var history: seq[StateStoreSnapshot] = @[fixture.view.finalizedBlock.value.stateSnapshot]
  for index in 0..<fixture.view.retainedCount-1:
    history.add(fixture.view.retainedBlockAt(RetainedBlockIndex(index)).value.stateSnapshot)
  let generation = RepositoryGeneration(uint64(history.len)+1)
  let context = encodeDiskHistory(owner, default(StorageChainId), generation,
      limits.contextBytes).value
  var disk = default(DiskStateStore)
  let path = "managed-retained-bootstrap"
  defer:
    if disk.opened: discard disk.close
  var short = limits
  short.roots = ElementLimit(8)
  assert initializeManagedDiskStateStore(disk, path, default(StorageChainId),
      owner.stateSnapshot.value,
    short, StorageSchema.FullStateV1, context, history).fileError == FileError.LimitExceeded
  assert not disk.opened
  assert initializeManagedDiskStateStore(disk, path, default(StorageChainId),
      owner.stateSnapshot.value,
    limits, StorageSchema.FullStateV1, context, history).error == DiskStoreError.None
  assert uint64(disk.generation.value) == uint64(generation)
  assert disk.managedDiskUsage.value.journalBytes == uint64(ManagedJournalHeaderBytes)
  assert disk.close == FileError.None
  assert openLocalManagedDiskStateStore(disk, path, default(StorageChainId), fixture.policy,
      limits).error == DiskStoreError.None
  let restored = restoreDiskHistory(disk.snapshotContext.value, default(StorageChainId), generation,
    fixture.view.bestBlock.value.chainParameters, disk, fixture.policy, limits.contextBytes).value
  assert sameStateSnapshot(restored.stateSnapshot.value, disk.snapshot.value)
  assert restored.chainView.retainedCount == MaxRetainedBlocks
  assert array[32, byte](restored.chainView.finalizedBlock.value.blockHash) == array[32, byte](
      fixture.view.finalizedBlock.value.blockHash)
  for index in 0..<fixture.view.retainedCount:
    let expected = fixture.view.retainedBlockAt(RetainedBlockIndex(index)).value
    let selected = restored.chainView.blockAt(expected.blockHash).value
    for ordinal in 0..<expected.stateSnapshot.commitment.entries:
      let key = expected.stateSnapshot.keyAt(StateEntryIndex(ordinal)).value
      assert selected.stateSnapshot.lookup(key).value.bytes == expected.stateSnapshot.lookup(
          key).value.bytes
  let finalized = disk.restoreDiskSnapshot(fixture.view.finalizedBlock.value.stateRoot,
      fixture.policy).value
  assert array[32, byte](finalized.commitment.root) == array[32, byte](
      fixture.view.finalizedBlock.value.stateRoot)
  assert disk.close == FileError.None
  removeManagedSample(path, [ManagedEpoch(1)])
try:
  main()
except:
  quit(2)
echo "PASS managed retained bootstrap: atomic nine-root seed, exact context, bounded history and separated finality"
