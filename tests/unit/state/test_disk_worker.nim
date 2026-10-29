# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual native durable commits preserve graph leases, receipts and bounded slot ownership through shutdown.
import std/[assertions, envvars, syncio, monotimes, times]
import std/posix/posix
import ../../support/[durable_chain_context, accumulation_completion_context]
import ../../../src/app/chain
import ../../../src/app/disk/[chain as disk_chain, worker as disk_worker]
import ../../../src/chain/provider
import ../../../src/state/[store, disk_store]
import ../../../src/state/accumulation/publication as accumulation_publication
import ../../../src/storage/file/repository as file_repository
import ../../../src/storage/node/[repository as node_repository, records as node_records]
import ../../../src/storage/[record_codec, database_identity]
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie
import ../../../src/codec/report_owned
proc workerPid(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## Process-private paged namespaces never replace another native test's artifact.
proc journalLimits(): JournalLimits =
  ## Explicit broad fixture ceilings bound all physical records, individual batches and history context.
  JournalLimits(repository: RepositoryLimits(codec: RecordLimits(trie: StateTrieLimits(
    items: ElementLimit(100000), perValue: ByteLimit(1048576), totalValueBytes: ByteLimit(16777216),
    nodes: TrieNodeLimit(1000000)), records: TrieExportLimits(records: TrieNodeLimit(1000000),
      valueBytes: ByteLimit(16777216)), encoded: ByteLimit(33554432)),
    records: ElementLimit(2000000), valueBytes: ByteLimit(67108864)),
    bytes: ByteLimit(134217728), contextBytes: ByteLimit(1048576))
proc waitDone(worker: var DiskPublicationWorker) =
  ## Only scalar worker state is touched while every leased ARC alias remains frozen.
  let started = getMonoTime()
  while worker.phase != DiskWorkerPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20, "bounded native completion"
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Yield under a monotonic bounded test deadline.
proc cycle(seed: ApplicationChain, prepared: PreparedChainUpdate, mode: int,
    paged = false, replay = false) {.raises.} =
  ## Modes collect normally, join a completed operation, or race joined shutdown against native entry.
  var owner = seed
  var disk = default(DiskStateStore)
  var worker = default(DiskPublicationWorker)
  var path = "disk-worker.db"
  if paged: path = path & "-paged-" & $workerPid() & "-" &
      $mode & "-replay-" & $replay # Separate explicitly owned paged namespaces survive fixture retirement.
  let limits = journalLimits()
  let chain = default(StorageChainId)
  defer:
    discard worker.close # Join before disk, publication, application or retained fixture aliases retire.
    if disk.opened: discard disk.close
  if paged:
    discard initializePagedDiskChain(disk, path, chain, owner,
        limits).value # One artifact binds retained complete roots and application context.
  else:
    discard initializeDiskChain(disk, path, chain, owner,
        limits).value # Existing journal worker behavior remains qualified.
  defer:
    if not paged: discard posix.unlink(path.toCString()) # Paged directory artifacts remain in the ignored runner namespace for inspection.
  var publication = prepareDiskPublication(disk, owner, prepared, chain, limits.contextBytes,
      replay = replay).value
  assert worker.submit(disk, publication).error == DiskWorkerError.Closed, "start native worker"
  assert worker.start(), "live worker cannot restart"
  assert not worker.start(), "live worker cannot restart"
  var absent = default(PreparedDiskPublication)
  assert worker.submit(disk, absent).error == DiskWorkerError.NotReady, "default publication refuses admission"
  let before = disk.generation.value
  let admitted = worker.submit(disk, publication)
  assert admitted.error == DiskWorkerError.None, "ready publication admits one job"
  let ticket = admitted.value
  assert worker.submit(disk, publication).error == DiskWorkerError.Busy, "default ticket grants no completion"
  assert worker.collect(default(DiskPublicationTicket)).kind == DiskCompletionKind.Uninitialized, "default ticket grants no completion"
  var completion = default(DiskPublicationCompletion)
  if mode == 2:
    completion = worker.close # Never discard a possible commit receipt during a shutdown race.
  else:
    worker.waitDone()
    assert worker.submit(disk, publication).error == DiskWorkerError.Busy, "Done retains capacity"
    if mode == 1:
      completion = worker.close # A completed native commit remains visible to the joining host.
    else:
      completion = worker.collect(ticket)
      assert worker.collect(ticket).kind == DiskCompletionKind.Uninitialized, "canonical owner unchanged by IO worker"
  assert sameStateSnapshot(owner.stateSnapshot.value, seed.stateSnapshot.value), "canonical owner unchanged by native IO"
  if completion.kind == DiskCompletionKind.Completed:
    assert completion.value.error == DiskChainError.None, "exact durable generation"
    assert uint64(completion.value.value) == uint64(before)+1, "disk owns exact prepared target"
    assert sameStateSnapshot(disk.snapshot.value, prepared.stateSnapshot), "disk owns exact prepared target"
    owner.installPrepared(publication.chainUpdate) # Only the host installs after the complete receipt and ended lease.
    assert sameStateSnapshot(owner.stateSnapshot.value, disk.snapshot.value), "host install matches durable target"
    if mode == 0:
      let stale = worker.submit(disk, publication).value
      worker.waitDone()
      assert worker.collect(stale).value.error == DiskChainError.CanonicalMismatch, "stale publication retains typed refusal"
      assert uint64(disk.generation.value) == uint64(before)+1, "stale publication cannot advance generation"
  else:
    assert mode == 2 and completion.kind == DiskCompletionKind.NotExecuted, "unexecuted shutdown has no receipt"
    assert uint64(disk.generation.value) == uint64(before), "unexecuted shutdown preserves generation"
    assert sameStateSnapshot(disk.snapshot.value, seed.stateSnapshot.value), "unexecuted shutdown preserves state owner"
  discard worker.close
  assert worker.start(), "closed worker can restart"
  assert worker.collect(ticket).kind == DiskCompletionKind.Uninitialized, "old ticket cannot retire restarted worker"
  assert worker.close.kind == DiskCompletionKind.Uninitialized, "idle joined shutdown has no receipt"
proc main() {.raises.} =
  ## Repeat complete start/commit/join/close lifetimes; public allocator counters are per-thread, not process totals.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let fixture = durableFixture(decodeOwnedReport(bytes, 2).value)
  let seed = initApplicationChain(genesisView(fixture.parent)).value
  let prepared = seed.prepareAccumulation(fixture.source, completionLimits().composition).value
  for mode in 0..2: cycle(seed, prepared, mode)
  for mode in 0..2: cycle(seed, prepared, mode, true) # Both update families use the same excluded native worker for paged commits.
  for mode in 0..2: cycle(seed, prepared, mode, true,
      true) # Explicit replay uses independently prepared genuine updates on the same worker.
  for index in 0..<24: cycle(seed, prepared, index mod 3)
try:
  main()
except:
  quit(2) # Fixture, thread and real IO failures cannot count as passing lifetime evidence.
echo "PASS disk worker: actual native commits, exclusive graph leases, exact receipts, stale tickets and joined ownership release"
