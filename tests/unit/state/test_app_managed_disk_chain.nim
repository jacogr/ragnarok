# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed chain startup preserves canonical history/context/finality without exposing an intermediate bootstrap head.
import std/assertions
import std/syncio
import ../../support/storage_disk_history_context
import ../../support/app_managed_storage_samples
import ../../../src/app/chain as app_chain
import ../../../src/app/disk_chain as app_disk_chain
import ../../../src/app/disk_history as app_disk_history
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/state/store as state_store
import ../../../src/state/disk_store as state_disk_store
import ../../../src/storage/file_repository as storage_file_repository
import ../../../src/storage/managed_repository as storage_managed_repository
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/record_codec as storage_record_codec
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie
proc main() {.raises.} =
  ## Complete structured local maps exercise startup binding; malformed selected metadata never grants fallback.
  let fixture = diskHistoryFixture()
  let owner = initApplicationChain(fixture.view).value
  let limits = ManagedLimits(repository: RepositoryLimits(codec: RecordLimits(
    trie: fixture.policy.trie, records: TrieExportLimits(records: TrieNodeLimit(100000),
      valueBytes: ByteLimit(1048576)), encoded: ByteLimit(4194304)), records: ElementLimit(100000),
      valueBytes: ByteLimit(16777216)), roots: ElementLimit(9), snapshotBytes: ByteLimit(33554432),
      journalBytes: ByteLimit(33554432), contextBytes: ByteLimit(1048576))
  var disk = default(DiskStateStore)
  let path = "managed-disk-chain"
  defer:
    if disk.opened: discard disk.close
  let initialized = initializeManagedDiskChain(disk, path, default(StorageChainId), owner, limits)
  assert initialized.error == DiskChainError.None and uint64(initialized.value) == 9
  let context = disk.snapshotContext.value
  assert disk.managedDiskUsage.value.journalBytes == uint64(ManagedJournalHeaderBytes)
  assert initializeManagedDiskChain(disk, path, default(StorageChainId), owner, limits).error ==
      DiskChainError.Busy
  assert disk.close == FileError.None
  let restored = openManagedDiskChain(disk, path, default(StorageChainId),
    fixture.view.bestBlock.value.chainParameters, fixture.policy, limits).value
  assert sameStateSnapshot(restored.stateSnapshot.value, disk.snapshot.value)
  assert disk.snapshotContext.value == context
  assert restored.chainView.retainedCount == MaxRetainedBlocks
  assert array[32, byte](restored.chainView.finalizedBlock.value.blockHash) == array[32, byte](
      fixture.view.finalizedBlock.value.blockHash)
  for index in 0..<fixture.view.retainedCount:
    let expected = fixture.view.retainedBlockAt(RetainedBlockIndex(index)).value
    let selected = restored.chainView.blockAt(expected.blockHash).value
    assert array[32, byte](selected.stateRoot) == array[32, byte](expected.stateRoot)
  assert disk.close == FileError.None
  var wrong = default(array[32, byte])
  wrong[0] = 1
  let refused = openManagedDiskChain(disk, path, StorageChainId(wrong),
    fixture.view.bestBlock.value.chainParameters, fixture.policy, limits)
  assert refused.storeFailure.fileError == FileError.WrongIdentity and not disk.opened
  assert initializeManagedDiskChain(disk, path, default(StorageChainId), owner,
      limits).storeFailure.fileError == FileError.AlreadyExists
  assert not disk.opened
  removeManagedSample(path, [ManagedEpoch(1)])
try:
  main()
except:
  quit(2)
echo "PASS managed disk chain: atomic canonical bootstrap, local history/finality binding and identity refusal"
