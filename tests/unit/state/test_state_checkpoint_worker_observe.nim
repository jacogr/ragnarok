# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_checkpoint_worker_observe_arc_release"}

## Selector observations share the single worker slot and never confer independent root trust.

import std/[assertions, syncio, monotimes, times]
import std/posix/posix
import ../../../src/state/checkpoint/[worker as checkpoint_worker, bank as checkpoint_bank,
    transfer as checkpoint_transfer, head as checkpoint_head]
import ../../../src/state/[checkpoint, store]
import ../../../src/lib/atomic/file as atomic_file
import ../../../src/codec/state/[trie as state_trie, layout as state_layout]
import ../../../src/codec/bounded
import ../../support/arc_evidence

const Prefix = "state-checkpoint-worker-observe"
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
proc observe(worker: var CheckpointWorker): CheckpointCompletion =
  ## Real native reads retire before host-only acknowledgement releases capacity.
  let ticket = worker.stageHead().value
  assert worker.begin(ticket)
  worker.waitDone()
  assert worker.stageHead().error == CheckpointWorkerError.Busy
  assert worker.retry(ticket, default(CheckpointHead)).error == CheckpointWorkerError.NotReady
  worker.collect(ticket)
proc cycle(worker: var CheckpointWorker, expected: CheckpointHead) =
  ## Independent scalar receipts match exact generation, slot and root without retaining worker ownership.
  let receipt = observe(worker)
  assert receipt.kind == CheckpointCompletionKind.Completed
  assert receipt.value.error == CheckpointBankError.None
  let head = receipt.value.value
  assert uint64(head.generation) == uint64(expected.generation) and head.slot == expected.slot
  assert array[32, byte](head.root) == array[32, byte](expected.root)
proc main() {.raises.} =
  ## Missing, malformed and oversized metadata never becomes a successful observation; cancellation performs no read.
  for suffix in [".head", ".0", ".1"]:
    var path = Prefix & suffix
    discard posix.unlink(path.toCString()) # Reset only this test namespace before worker startup.
  defer:
    for suffix in [".head", ".head.lock", ".0", ".1"]:
      var path = Prefix & suffix
      discard posix.unlink(path.toCString()) # Explicit joined close precedes native lock inode cleanup.
  var worker = default(CheckpointWorker)
  defer: discard worker.close()
  assert worker.stageHead().error == CheckpointWorkerError.Closed
  assert worker.start(Prefix) == CheckpointBankError.None
  let cancelled = worker.stageHead().value
  assert worker.cancel(cancelled)
  assert worker.collect(cancelled).kind == CheckpointCompletionKind.Cancelled
  assert observe(worker).value.error == CheckpointBankError.IoFailure
  var initial = detached(7)
  let ticket = worker.stage(initial, CheckpointOperation.Bootstrap, default(CheckpointHead),
      ByteLimit(1000)).value
  assert worker.begin(ticket)
  worker.waitDone()
  let expected = worker.collect(ticket).value.value
  let original = readBoundedFile(Prefix & ".head", ByteLimit(1000)).value
  cycle(worker, expected)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(worker, expected) # Host occupancy covers receipts and ticket namespaces, not the native allocator.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_checkpoint_worker_observe", 1000, before, after)
  var corrupt = original
  corrupt[0] = corrupt[0] xor 1
  assert replaceAtomicFile(Prefix & ".head", corrupt, ByteLimit(1000)) == AtomicFileError.None
  let invalid = observe(worker)
  assert invalid.value.error == CheckpointBankError.InvalidHead
  assert invalid.value.headError == CheckpointHeadError.InvalidFormat
  corrupt = original
  corrupt.add(0)
  assert replaceAtomicFile(Prefix & ".head", corrupt, ByteLimit(1000)) == AtomicFileError.None
  assert observe(worker).value.error == CheckpointBankError.LimitExceeded
  assert replaceAtomicFile(Prefix & ".head", original, ByteLimit(1000)) == AtomicFileError.None
  cycle(worker, expected)
  assert worker.close().retirementError == CheckpointBankError.None
  echo "PASS checkpoint observation: bounded asynchronous selector reads and explicit untrusted metadata"
try:
  main() # Startup and thread failures are nonzero suite failures, never successful metadata reads.
except:
  quit(2)
