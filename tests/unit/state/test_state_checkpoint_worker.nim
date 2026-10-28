# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_checkpoint_worker_arc_release"}

## Real I/O threads consume independent buffers under bounded backpressure and report actual joined publication receipts.

import std/assertions
import std/syncio
import std/monotimes
import std/times
import std/posix/posix
import ../../../src/state/checkpoint_worker as state_checkpoint_worker
import ../../../src/state/checkpoint_bank as state_checkpoint_bank
import ../../../src/state/checkpoint_transfer as state_checkpoint_transfer
import ../../../src/state/checkpoint_head as state_checkpoint_head
import ../../../src/state/checkpoint_file as state_checkpoint_file
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/state/store as state_store
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/bounded as codec_bounded
import ../../support/testing_arc_evidence

const Prefix = "state-checkpoint-worker"
proc policy(): StateStoreLimits =
  ## Small complete maps provide distinct roots without unrelated block execution or protocol assumptions.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(100),
    totalValueBytes: ByteLimit(200), nodes: TrieNodeLimit(1024)), writes: ElementLimit(4),
        writeValueBytes: ByteLimit(200))
proc detached(value: byte): PreparedCheckpoint =
  ## Every original complete-map alias retires before the independent encoded owner is staged.
  let snapshot = newStateStore([StateEntry(key: default(StateKey), value: @[value])], policy()).value.snapshot.value
  prepareFullCheckpoint(snapshot, ByteLimit(1000))
proc waitDone(worker: var CheckpointWorker) =
  ## Scalar-only test polling yields to the actual I/O thread under a monotonic deadline.
  let started = getMonoTime()
  while worker.phase != CheckpointWorkerPhase.Done:
    assert (getMonoTime() - started).inSeconds < 20, "bounded I/O worker completion"
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # This is test scheduling, never production polling or a storage latency guarantee.
proc cycle(worker: var CheckpointWorker, head: var CheckpointHead) =
  ## Host-created private buffers return to their own allocator thread only after worker-local aliases retire.
  var prepared = detached(3)
  let expectedRoot = prepared.root
  let admitted = worker.stage(prepared, CheckpointOperation.Advance, head, ByteLimit(1000))
  assert admitted.error == CheckpointWorkerError.None
  assert prepared.error == CheckpointError.Uninitialized
  assert worker.begin(admitted.value)
  worker.waitDone()
  let completed = worker.collect(admitted.value)
  assert completed.kind == CheckpointCompletionKind.Completed and completed.value.error ==
      CheckpointBankError.None
  head = completed.value.value
  assert array[32, byte](head.root) == array[32, byte](expectedRoot)
proc main() {.raises.} =
  ## No live canonical graph is borrowed; foreign/stale tickets, Done capacity and shutdown outcomes stay explicit.
  for suffix in [".head", ".0", ".1", "-foreign.head", "-foreign.0", "-foreign.1"]:
    var path = Prefix & suffix
    discard posix.unlink(path.toCString()) # Test-owned reset occurs before native bank acquisition.
  defer:
    for suffix in [".head", ".head.lock", ".0", ".1", "-foreign.head", "-foreign.head.lock",
        "-foreign.0", "-foreign.1"]:
      var path = Prefix & suffix
      discard posix.unlink(path.toCString()) # Native owners declared below join/close before their stable test-only lock inodes are removed.
  var inactive = default(CheckpointWorker)
  var relocated = move(inactive)
  assert inactive.close().retirementError == CheckpointBankError.None
  assert relocated.close().retirementError == CheckpointBankError.None # Inactive ownership may relocate without a live thread/native descriptor lifetime.
  var worker = default(CheckpointWorker)
  defer: discard worker.close()
  var foreign = default(CheckpointWorker)
  defer: discard foreign.close()
  var source = detached(1)
  let firstRoot = source.root
  assert worker.stage(source, CheckpointOperation.Bootstrap, default(CheckpointHead), ByteLimit(
      1000)).error == CheckpointWorkerError.Closed
  assert source.error == CheckpointError.None
  assert not worker.begin(default(CheckpointTicket))
  assert worker.collect(default(CheckpointTicket)).kind == CheckpointCompletionKind.Uninitialized
  assert worker.close().retirementError == CheckpointBankError.None
  assert worker.start("") == CheckpointBankError.InvalidPath
  assert worker.start(Prefix) == CheckpointBankError.None
  assert worker.start(Prefix) == CheckpointBankError.Busy
  assert foreign.start(Prefix & "-foreign") == CheckpointBankError.None
  var absent = default(PreparedCheckpoint)
  assert worker.stage(absent, CheckpointOperation.Bootstrap, default(CheckpointHead), ByteLimit(
      1000)).error == CheckpointWorkerError.NotReady
  assert worker.stage(source, CheckpointOperation.Advance, default(CheckpointHead), ByteLimit(
      1000)).error == CheckpointWorkerError.InvalidHead
  assert worker.stage(source, CheckpointOperation.Bootstrap, default(CheckpointHead), ByteLimit(
      0)).error == CheckpointWorkerError.LimitExceeded
  assert source.error == CheckpointError.None # All refused admissions preserve caller ownership.
  let admitted = worker.stage(source, CheckpointOperation.Bootstrap, default(CheckpointHead),
      ByteLimit(1000))
  assert admitted.error == CheckpointWorkerError.None
  let ticket = admitted.value
  assert source.error == CheckpointError.Uninitialized and worker.phase ==
      CheckpointWorkerPhase.Staged
  var queued = detached(2)
  let other = foreign.stage(queued, CheckpointOperation.Bootstrap, default(CheckpointHead),
      ByteLimit(1000)).value
  assert not worker.begin(other) and not foreign.begin(ticket)
  assert worker.collect(other).kind == CheckpointCompletionKind.Uninitialized
  assert worker.collect(ticket).kind == CheckpointCompletionKind.Uninitialized # Staged work performs no I/O and cannot be collected early.
  var busy = detached(2)
  assert worker.stage(busy, CheckpointOperation.Bootstrap, default(CheckpointHead), ByteLimit(
      1000)).error == CheckpointWorkerError.Busy
  assert busy.error == CheckpointError.None
  assert worker.begin(ticket)
  assert not worker.begin(ticket)
  worker.waitDone()
  assert worker.stage(busy, CheckpointOperation.Bootstrap, default(CheckpointHead), ByteLimit(
      1000)).error == CheckpointWorkerError.Busy # Done still owns capacity until the matching collection.
  var head = worker.collect(ticket).value.value
  assert array[32, byte](head.root) == array[32, byte](firstRoot) and uint64(head.generation) == 0
  assert loadFullCheckpoint(Prefix & ".0", firstRoot, policy(), ByteLimit(1000)).error ==
      CheckpointFileError.None
  assert worker.collect(ticket).kind == CheckpointCompletionKind.Uninitialized
  assert not worker.begin(ticket)
  let foreignShutdown = foreign.close()
  assert foreignShutdown.retirementError == CheckpointBankError.None and
      foreignShutdown.completion.kind ==
      CheckpointCompletionKind.Cancelled # Staged foreign work never began and creates no committed head.
  let stale = newCheckpointHead(CheckpointGeneration(1), head.slot, head.root)
  let refused = worker.stage(busy, CheckpointOperation.Advance, stale, ByteLimit(1000)).value
  assert worker.begin(refused)
  worker.waitDone()
  let failure = worker.collect(refused)
  assert failure.kind == CheckpointCompletionKind.Completed and failure.value.error ==
      CheckpointBankError.StaleHead # Completed preserves actual typed bank failure rather than granting adoption.
  cycle(worker, head)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(worker, head) # This records host buffer/ticket release, not total worker-thread allocator occupancy.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_checkpoint_worker", 1000, before, after)
  let idle = worker.close()
  assert idle.retirementError == CheckpointBankError.None and idle.completion.kind ==
      CheckpointCompletionKind.Uninitialized
  assert worker.start(Prefix) == CheckpointBankError.None
  var restart = detached(4)
  let later = worker.stage(restart, CheckpointOperation.Advance, head, ByteLimit(1000)).value
  assert not worker.begin(ticket) and worker.collect(ticket).kind ==
      CheckpointCompletionKind.Uninitialized # Equal local generations cannot revive a retained ticket from an old namespace.
  let cancelled = worker.close()
  assert cancelled.retirementError == CheckpointBankError.None and cancelled.completion.kind ==
      CheckpointCompletionKind.Cancelled
  var observer = default(CheckpointBank)
  defer: discard observer.close()
  assert observer.openCheckpointBank(Prefix) == CheckpointBankError.None
  assert uint64(observer.selectedHead().value.generation) == uint64(
      head.generation) # Joined staged shutdown performs no hidden publication.
  assert observer.close() == CheckpointBankError.None
  assert worker.start(Prefix) == CheckpointBankError.None
  var completedSource = detached(5)
  let finished = worker.stage(completedSource, CheckpointOperation.Advance, head, ByteLimit(1000)).value
  assert worker.begin(finished)
  worker.waitDone()
  let joined = worker.close()
  assert joined.retirementError == CheckpointBankError.None and joined.completion.kind ==
      CheckpointCompletionKind.Completed
  assert joined.completion.value.error == CheckpointBankError.None
  head = joined.completion.value.value # Shutdown preserves a real committed receipt without collection.
  assert worker.start(Prefix) == CheckpointBankError.None
  var runningSource = detached(6)
  let running = worker.stage(runningSource, CheckpointOperation.Advance, head, ByteLimit(1000)).value
  assert worker.begin(running)
  let shutdown = worker.close() # Join either skips unentered work or waits for actual running I/O; neither can outlive the owner.
  assert shutdown.retirementError == CheckpointBankError.None
  if shutdown.completion.kind == CheckpointCompletionKind.Completed:
    assert shutdown.completion.value.error == CheckpointBankError.None
    head = shutdown.completion.value.value # Any actual commit must be reflected in the returned receipt.
  else:
    assert shutdown.completion.kind == CheckpointCompletionKind.Cancelled # Interrupted execution is never accepted as a successful normal join.
  assert observer.openCheckpointBank(Prefix) == CheckpointBankError.None
  let actual = observer.selectedHead().value
  assert uint64(actual.generation) == uint64(head.generation) and array[32, byte](actual.root) ==
      array[32, byte](head.root)
  assert observer.restore(head.root, policy(), ByteLimit(1000)).error == CheckpointBankError.None
  assert observer.close() == CheckpointBankError.None
  echo "PASS checkpoint I/O worker: detached ownership, bounded dispatch, exact receipts and joined shutdown"
try:
  main() # Thread or SDK startup failure is a failing suite, never a successful I/O refusal control.
except:
  quit(2)
