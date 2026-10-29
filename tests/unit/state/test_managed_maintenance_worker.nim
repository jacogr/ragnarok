# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One native slot serializes managed maintenance with publication and retains every entered IO receipt through shutdown.
import std/[assertions, syncio, monotimes, times]
import std/posix/posix
import ../../support/[disk_history_context, managed_storage_samples, managed_disk_history_context]
import ../../../src/app/chain
import ../../../src/app/disk/[chain as disk_chain, worker as disk_worker]
import ../../../src/chain/[genesis, provider]
import ../../../src/state/[store, disk_store]
import ../../../src/storage/file/repository as file_repository
import ../../../src/storage/managed/[repository as managed_repository, manifest as managed_manifest]
import ../../../src/storage/node/repository as node_repository
import ../../../src/storage/database_identity
proc waitDone(worker: var DiskPublicationWorker) =
  ## Only scalar state is observed until collection or joined shutdown ends every exclusive graph borrow.
  let started = getMonoTime()
  while worker.phase != DiskWorkerPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    var request = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(request, remaining)
proc cycle(mode: int) {.raises.} =
  ## Modes cover explicit collection, completed joined close, and a queued/executing shutdown race.
  let fixture = diskHistoryFixture()
  let owner = initApplicationChain(fixture.view).value
  let limits = managedHistoryLimits(fixture.policy)
  var disk = default(DiskStateStore)
  var worker = default(DiskPublicationWorker)
  let path = "managed-maintenance-worker-" & $mode
  defer:
    discard worker.close
    if disk.opened: discard disk.close
  assert initializeManagedDiskChain(disk, path, default(StorageChainId), owner, limits).error ==
      DiskChainError.None
  var plan = prepareDiskMaintenance(disk, owner, default(StorageChainId), limits.contextBytes).value
  var absent = default(PreparedDiskMaintenance)
  var publication = default(PreparedDiskPublication)
  let before = disk.snapshot.value
  let generation = disk.generation.value
  assert worker.submitMaintenance(disk, plan).error == DiskWorkerError.Closed
  assert worker.start()
  assert worker.submitMaintenance(disk, absent).error == DiskWorkerError.NotReady
  let ticket = worker.submitMaintenance(disk, plan).value
  assert worker.submit(disk, publication).error == DiskWorkerError.Busy
  assert worker.submitMaintenance(disk, plan).error == DiskWorkerError.Busy
  assert worker.collect(default(DiskPublicationTicket)).kind == DiskCompletionKind.Uninitialized
  var completion = default(DiskPublicationCompletion)
  if mode == 2:
    completion = worker.close # Joined shutdown cannot discard a maintenance operation that entered IO.
  else:
    worker.waitDone()
    assert worker.submit(disk, publication).error == DiskWorkerError.Busy
    if mode == 1: completion = worker.close
    else: completion = worker.collect(ticket)
  if completion.kind == DiskCompletionKind.Maintained:
    assert completion.maintenanceValue.error == DiskChainError.None
    assert uint64(completion.maintenanceValue.value.epoch) == 2
    assert uint64(disk.managedDiskUsage.value.epoch) == 2
  else:
    assert mode == 2 and completion.kind == DiskCompletionKind.NotExecuted
    assert uint64(disk.managedDiskUsage.value.epoch) == 1
  assert sameStateSnapshot(before, disk.snapshot.value)
  assert uint64(disk.generation.value) == uint64(generation)
  if mode == 0:
    assert worker.collect(ticket).kind == DiskCompletionKind.Uninitialized
    let reused = worker.submitMaintenance(disk, plan).value
    worker.waitDone()
    assert worker.collect(reused).maintenanceValue.error == DiskChainError.CanonicalMismatch
  discard worker.close
  assert disk.close == FileError.None
  let restored = openManagedDiskChain(disk, path, default(StorageChainId),
    fixture.view.bestBlock.value.chainParameters, fixture.policy, limits).value
  assert restored.chainView.retainedCount == MaxRetainedBlocks
  assert array[32, byte](restored.chainView.finalizedBlock.value.blockHash) == array[32, byte](
      fixture.view.finalizedBlock.value.blockHash)
  assert disk.close == FileError.None
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
proc main() {.raises.} =
  ## Each isolated lifecycle owns one stable worker address and one managed directory lock.
  for mode in 0..2: cycle(mode)
try:
  main()
except:
  quit(2)
echo "PASS managed maintenance worker: one-slot exclusion, exact receipts, stale requests and joined shutdown"
