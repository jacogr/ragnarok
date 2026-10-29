# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine current updates use the existing native one-slot worker without losing IO receipts or touching canonical ownership.
import std/[assertions, envvars, syncio]
import std/posix/posix
import ../../support/report_context as signed_fixture
import ../../../src/app/chain
import ../../../src/app/disk/[chain as disk_chain, worker as disk_worker]
import ../../../src/app/historical/disk as historical_disk
import ../../../src/chain/provider
import ../../../src/state/[store, disk_store]
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/storage/file/repository as file_repository
import ../../../src/storage/node/repository as node_repository
import ../../../src/storage/database_identity
import ../../../src/storage/history/index as history_index
import ../../../src/codec/[bounded, report_owned]
import ../../support/[accumulation_current_chain_context, accumulation_current_disk_context, accumulation_provision_integration]
proc workerPid(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## Process-private paged namespaces never replace another native test's artifact.
proc cycle(original: ApplicationChain, update: PreparedCurrentChainUpdate, mode: int,
    paged = false, replay = false) {.raises.} =
  ## Collect, joined-Done shutdown and immediate joined shutdown all preserve the exact actual operation outcome.
  var owner = original
  var disk = default(DiskStateStore)
  var worker = default(DiskPublicationWorker)
  var publication = default(PreparedCurrentDiskPublication)
  assert worker.submit(disk, publication).error == DiskWorkerError.Closed
  assert worker.start()
  assert worker.submit(disk, publication).error == DiskWorkerError.NotReady
  discard worker.close
  var path = "current-disk-worker.db"
  if paged: path = path & "-paged-" & $workerPid() & "-" &
      $mode & "-replay-" & $replay # Separate explicitly owned paged namespaces survive fixture retirement.
  let limits = currentDiskLimits()
  let identity = default(StorageChainId)
  defer:
    discard worker.close # Every native borrower retires before any publication, disk or canonical graph alias.
    if disk.opened: discard disk.close
  let initialized = if paged: initializePagedDiskChain(disk, path, identity, owner, limits).value
    else: initializeDiskChain(disk, path, identity, owner, limits).value
  defer:
    if not paged: discard posix.unlink(path.toCString()) # Paged directory artifacts remain in the ignored runner namespace for inspection.
  let before = configureDiskHistory(disk, owner, identity, archiveHistoryPolicy(),
      limits.contextBytes).value
  assert uint64(before) >= uint64(initialized)
  publication = prepareDiskPublication(disk, owner, update, identity, limits.contextBytes,
      replay = replay).value
  assert worker.start()
  let ticket = worker.submit(disk, publication).value
  assert worker.collect(default(DiskPublicationTicket)).kind == DiskCompletionKind.Uninitialized
  var completed = default(DiskPublicationCompletion)
  if mode == 2:
    completed = worker.close # Queued-only exit returns NotExecuted; entered IO always returns its actual receipt.
  else:
    worker.waitCurrentDiskDone()
    assert worker.submit(disk, publication).error == DiskWorkerError.Busy
    if mode == 1:
      completed = worker.close # Joining Done must return the same durable result as collection.
    else:
      completed = worker.collect(ticket)
      assert worker.collect(ticket).kind == DiskCompletionKind.Uninitialized
  assert sameStateSnapshot(owner.stateSnapshot.value, original.stateSnapshot.value)
  if completed.kind == DiskCompletionKind.Completed:
    assert completed.value.error == DiskChainError.None
    assert uint64(completed.value.value) == uint64(before)+1
    assert sameStateSnapshot(disk.snapshot.value, update.currentUpdateState)
    owner.installPrepared(publication.chainUpdate) # Only the host installs after collection/join has ended every borrowed activation.
    assert sameStateSnapshot(owner.stateSnapshot.value, disk.snapshot.value)
    let saved = readDiskHistoricalSnapshot(disk, owner, identity,
      owner.chainView.bestBlock.value.blockHash,
      signed_fixture.limits(), limits.contextBytes).value
    assert saved.chainView.bestBlock.value.blockBody == owner.chainView.bestBlock.value.blockBody
    assert array[32, byte](saved.stateSnapshot.value.commitment.root) == array[32, byte](
        owner.stateSnapshot.value.commitment.root)
    if mode == 0:
      let stale = worker.submit(disk, publication).value
      worker.waitCurrentDiskDone()
      let refused = worker.collect(stale)
      assert refused.kind == DiskCompletionKind.Completed
      assert refused.value.error == DiskChainError.CanonicalMismatch
      assert uint64(disk.generation.value) == uint64(before)+1
  else:
    assert mode == 2 and completed.kind == DiskCompletionKind.NotExecuted
    assert uint64(disk.generation.value) == uint64(before)
    assert sameStateSnapshot(disk.snapshot.value, original.stateSnapshot.value)
  discard worker.close
  assert worker.start()
  assert worker.collect(ticket).kind == DiskCompletionKind.Uninitialized
  assert worker.close.kind == DiskCompletionKind.Uninitialized
proc main() {.raises.} =
  ## Public allocator counters are per-thread, so repeated joined thread lifetimes are tested without a false process-wide ARC claim.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let context = currentChainFixture(decodeOwnedReport(bytes, 2).value, available = true, blobs = true)
  let original = initApplicationChain(context.currentChainSeeded).value
  let update = original.prepareAccumulation(context.source, ByteLimit(100000)).value
  for mode in 0..2: cycle(original, update, mode)
  for mode in 0..2: cycle(original, update, mode, true) # Both update families use the same excluded native worker for paged commits.
  for mode in 0..2: cycle(original, update, mode, true,
      true) # Explicit replay uses independently prepared genuine updates on the same worker.
  for iteration in 0..<24: cycle(original, update,
      iteration mod 3) # Repeat real publication/start/join lifetimes across all allowed shutdown outcomes.
try:
  main() # Actual thread or file failures cannot pass this current payload qualification.
except:
  quit(2)
echo "PVM current disk worker passed"
