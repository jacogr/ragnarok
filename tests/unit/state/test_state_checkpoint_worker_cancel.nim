# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_checkpoint_worker_cancel_arc_release"}

## Staged cancellation is deterministic, retains receipt backpressure and never hides dispatched publication.

import std/assertions
import std/syncio
import std/monotimes
import std/times
import std/posix/posix
import ../../../src/state/checkpoint_worker as state_checkpoint_worker
import ../../../src/state/checkpoint_bank as state_checkpoint_bank
import ../../../src/state/checkpoint_transfer as state_checkpoint_transfer
import ../../../src/state/checkpoint_head as state_checkpoint_head
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/state/store as state_store
import ../../../src/lib/atomic_file as lib_atomic_file
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/bounded as codec_bounded
import ../../support/testing_arc_evidence

const Prefix = "state-checkpoint-worker-cancel"
proc policy(): StateStoreLimits =
  ## Small complete maps make any unexpected publication visible through a different root.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(100),
    totalValueBytes: ByteLimit(200), nodes: TrieNodeLimit(1024)), writes: ElementLimit(4),
        writeValueBytes: ByteLimit(200))
proc detached(value: byte): PreparedCheckpoint =
  ## Source maps retire before their independent exclusive buffers enter the worker.
  let snapshot = newStateStore([StateEntry(key: default(StateKey), value: @[value])], policy()).value.snapshot.value
  prepareFullCheckpoint(snapshot, ByteLimit(1000))
proc waitDone(worker: var CheckpointWorker) =
  ## Test-only scalar polling yields to real I/O under an explicit monotonic deadline.
  let start = getMonoTime()
  while worker.phase != CheckpointWorkerPhase.Done:
    assert (getMonoTime() - start).inSeconds < 20, "bounded cancellation-control publication"
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # No production polling/deadline is introduced.
proc cycle(worker: var CheckpointWorker, head: CheckpointHead) =
  ## Staged cancellation releases sole buffer bytes while retaining the acknowledgement slot until collection.
  var source = detached(2)
  let ticket = worker.stage(source, CheckpointOperation.Advance, head, ByteLimit(1000)).value
  assert source.error == CheckpointError.Uninitialized
  assert worker.cancel(ticket)
  assert worker.phase == CheckpointWorkerPhase.Done and not worker.begin(ticket)
  assert not worker.cancel(ticket) # Cancellation is one state transition, not a repeated retirement authority.
  var waiting = detached(3)
  assert worker.stage(waiting, CheckpointOperation.Advance, head, ByteLimit(1000)).error ==
      CheckpointWorkerError.Busy
  assert waiting.error == CheckpointError.None
  assert worker.collect(default(CheckpointTicket)).kind == CheckpointCompletionKind.Uninitialized
  assert worker.collect(ticket).kind == CheckpointCompletionKind.Cancelled
  assert worker.phase == CheckpointWorkerPhase.Idle and not worker.cancel(ticket)
proc main() {.raises.} =
  ## Old selector/data are exact across cancellations; running/done requests retain actual committed receipts.
  for suffix in [".head", ".0", ".1", "-foreign.head", "-foreign.0", "-foreign.1"]:
    var path = Prefix & suffix
    discard posix.unlink(path.toCString()) # Test-owned namespace reset precedes native owner acquisition.
  defer:
    for suffix in [".head", ".head.lock", ".0", ".1", "-foreign.head", "-foreign.head.lock",
        "-foreign.0", "-foreign.1"]:
      var path = Prefix & suffix
      discard posix.unlink(path.toCString()) # All worker descriptors retire before test-only stable inode cleanup.
  var worker = default(CheckpointWorker)
  defer: discard worker.close()
  var foreign = default(CheckpointWorker)
  defer: discard foreign.close()
  assert not worker.cancel(default(CheckpointTicket))
  assert worker.start(Prefix) == CheckpointBankError.None
  assert foreign.start(Prefix & "-foreign") == CheckpointBankError.None
  var initial = detached(1)
  let first = worker.stage(initial, CheckpointOperation.Bootstrap, default(CheckpointHead),
      ByteLimit(1000)).value
  assert worker.begin(first)
  worker.waitDone()
  assert not worker.cancel(first) # Even completed real I/O cannot be hidden behind a cancelled completion.
  let head = worker.collect(first).value.value
  let headBytes = readBoundedFile(Prefix & ".head", ByteLimit(1000)).value
  let slotBytes = readBoundedFile(Prefix & ".0", ByteLimit(1000)).value
  var otherSource = detached(9)
  let other = foreign.stage(otherSource, CheckpointOperation.Bootstrap, default(CheckpointHead),
      ByteLimit(1000)).value
  assert not worker.cancel(other) and not foreign.cancel(first)
  assert foreign.cancel(other) and foreign.collect(other).kind == CheckpointCompletionKind.Cancelled
  cycle(worker, head)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(worker, head) # Host buffers and ticket aliases retire without a single cancelled request entering native I/O.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_checkpoint_worker_cancel", 1000, before, after)
  assert readBoundedFile(Prefix & ".head", ByteLimit(1000)).value == headBytes
  assert readBoundedFile(Prefix & ".0", ByteLimit(1000)).value == slotBytes
  assert readBoundedFile(Prefix & ".1", ByteLimit(1000)).error ==
      AtomicFileError.IoFailure # Staged cancellations create no inactive canonical file.
  var dispatched = detached(4)
  let next = worker.stage(dispatched, CheckpointOperation.Advance, head, ByteLimit(1000)).value
  assert worker.begin(next)
  assert not worker.cancel(next) # Running, executing and done schedules all refuse cancellation after dispatch.
  worker.waitDone()
  let completed = worker.collect(next)
  assert completed.kind == CheckpointCompletionKind.Completed and completed.value.error ==
      CheckpointBankError.None
  let current = completed.value.value
  assert uint64(current.generation) == 1
  var last = detached(5)
  let pending = worker.stage(last, CheckpointOperation.Advance, current, ByteLimit(1000)).value
  assert worker.cancel(pending)
  let closed = worker.close()
  assert closed.retirementError == CheckpointBankError.None and closed.completion.kind ==
      CheckpointCompletionKind.Cancelled
  assert not worker.cancel(pending)
  var bank = default(CheckpointBank)
  defer: discard bank.close()
  assert bank.openCheckpointBank(Prefix) == CheckpointBankError.None
  assert uint64(bank.selectedHead().value.generation) == 1
  assert bank.restore(current.root, policy(), ByteLimit(1000)).error == CheckpointBankError.None
  assert bank.close() == CheckpointBankError.None
  echo "PASS checkpoint cancellation: staged-only retirement, retained capacity and honest running receipts"
try:
  main() # Thread or OS startup errors are suite failures, never accepted cancellation controls.
except:
  quit(2)
