# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque maintenance binds canonical state/context/generation/epoch and retains rolling roots plus explicit finality.
import std/[assertions, syncio]
import ../../support/[disk_history_context, managed_storage_samples, managed_disk_history_context]
import ../../../src/app/[chain, disk_chain, disk_history]
import ../../../src/chain/[genesis, provider]
import ../../../src/state/[store, disk_store]
import ../../../src/storage/[file_repository, managed_repository, managed_manifest, node_repository, database_identity]
import ../../../src/codec/bounded
proc main() {.raises.} =
  ## An unselected old map becomes reclaimable while the exact canonical source remains immutable.
  let fixture = diskHistoryFixture()
  let owner = initApplicationChain(fixture.view).value
  let limits = managedHistoryLimits(fixture.policy)
  let path = "managed-maintenance-plan"
  var disk = default(DiskStateStore)
  defer:
    if disk.opened: discard disk.close
  assert initializeManagedDiskChain(disk, path, default(StorageChainId), owner, limits).error ==
      DiskChainError.None
  assert not default(PreparedDiskMaintenance).ready
  assert commitDiskMaintenance(disk, default(PreparedDiskMaintenance)).error ==
      DiskChainError.Uninitialized
  let stale = prepareDiskMaintenance(disk, owner, default(StorageChainId),
      limits.contextBytes).value
  let transient = fixture.blocks[2].value.stateSnapshot
  assert disk.commit(owner.stateSnapshot.value, transient, [1'u8]).error == DiskStoreError.None
  assert prepareDiskMaintenance(disk, owner, default(StorageChainId), limits.contextBytes).error ==
      DiskChainError.CanonicalMismatch
  let generation = RepositoryGeneration(uint64(disk.generation.value)+1)
  let context = encodeDiskHistory(owner, default(StorageChainId), generation,
      limits.contextBytes).value
  assert disk.commit(transient, owner.stateSnapshot.value, context).error == DiskStoreError.None
  assert commitDiskMaintenance(disk, stale).error == DiskChainError.CanonicalMismatch
  let prepared = prepareDiskMaintenance(disk, owner, default(StorageChainId),
      limits.contextBytes).value
  assert prepared.ready
  let before = disk.snapshot.value
  let compacted = commitDiskMaintenance(disk, prepared).value
  assert compacted.reclaimedNodes > 0 and compacted.cleanup == FileError.None
  assert uint64(compacted.generation) == uint64(generation) and uint64(compacted.epoch) == 2
  assert sameStateSnapshot(before, disk.snapshot.value) and disk.snapshotContext.value == context
  assert commitDiskMaintenance(disk, prepared).error == DiskChainError.CanonicalMismatch
  assert disk.restoreDiskSnapshot(transient.commitment.root, fixture.policy).repositoryError ==
      RepositoryError.MissingNode
  assert disk.close == FileError.None
  let restored = openManagedDiskChain(disk, path, default(StorageChainId),
    fixture.view.bestBlock.value.chainParameters, fixture.policy, limits).value
  assert restored.chainView.retainedCount == MaxRetainedBlocks
  assert array[32, byte](restored.chainView.finalizedBlock.value.blockHash) == array[32, byte](
      fixture.view.finalizedBlock.value.blockHash)
  for index in 0..<fixture.view.retainedCount:
    let expected = fixture.view.retainedBlockAt(RetainedBlockIndex(index)).value
    assert disk.restoreDiskSnapshot(expected.stateRoot, fixture.policy).value.commitment.entries ==
        expected.stateSnapshot.commitment.entries
  assert prepareDiskMaintenance(disk, restored, default(StorageChainId), ByteLimit(1)).error ==
      DiskChainError.ContextFailure
  assert disk.close == FileError.None
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
try:
  main()
except:
  quit(2)
echo "PASS managed maintenance plan: exact canonical lease, explicit roots/finality, reclaimed history and stale epoch refusal"
