# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_checkpoint_worker_retry_arc_release"}

## Stale-head refusal may reuse its sole encoded buffer only through a fresh explicit expected-head ticket.

import std/[assertions, syncio, monotimes, times]
import std/posix/posix
import ../../../src/state/checkpoint/[worker as checkpoint_worker, bank as checkpoint_bank,
    transfer as checkpoint_transfer, head as checkpoint_head]
import ../../../src/state/[checkpoint, store]
import ../../../src/codec/state/[trie as state_trie, layout as state_layout]
import ../../../src/codec/bounded
import ../../support/arc_evidence

const Prefix = "state-checkpoint-worker-retry"
proc policy(): StateStoreLimits =
  ## Complete-map restoration remains bounded separately from the worker request's immutable byte ceiling.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(100),
    totalValueBytes: ByteLimit(200), nodes: TrieNodeLimit(1024)), writes: ElementLimit(4),
        writeValueBytes: ByteLimit(200))
proc detached(value: byte): PreparedCheckpoint =
  ## Only private encoded bytes survive source retirement; retry has no original map to re-encode or borrow.
  let snapshot = newStateStore([StateEntry(key: default(StateKey), value: @[value])], policy()).value.snapshot.value
  prepareFullCheckpoint(snapshot, ByteLimit(1000))
proc waitDone(worker: var CheckpointWorker) =
  ## A monotonic test deadline bounds scalar-only scheduling waits for real I/O completion.
  let started = getMonoTime()
  while worker.phase != CheckpointWorkerPhase.Done:
    assert (getMonoTime() - started).inSeconds < 20, "bounded retry worker completion"
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Production remains condition-driven and does not poll.
proc cycle(worker: var CheckpointWorker, head: var CheckpointHead) =
  ## Peek retains capacity; fresh retry reuses the same encoded owner and invalidates every old ticket.
  var source = detached(3)
  let root = source.root
  let stale = newCheckpointHead(CheckpointGeneration(0), head.slot, head.root)
  let old = worker.stage(source, CheckpointOperation.Advance, stale, ByteLimit(1000)).value
  assert worker.begin(old)
  worker.waitDone()
  assert worker.peek(old).value.error == CheckpointBankError.StaleHead
  let retried = worker.retry(old, head)
  assert retried.error == CheckpointWorkerError.None
  let ticket = retried.value
  assert source.error == CheckpointError.Uninitialized and worker.phase ==
      CheckpointWorkerPhase.Staged
  assert worker.peek(old).kind == CheckpointCompletionKind.Uninitialized
  assert worker.collect(old).kind == CheckpointCompletionKind.Uninitialized and not worker.begin(old)
  assert worker.retry(old, head).error == CheckpointWorkerError.NotReady
  assert worker.peek(ticket).kind == CheckpointCompletionKind.Uninitialized
  assert worker.begin(ticket)
  worker.waitDone()
  let observed = worker.peek(ticket)
  assert observed.kind == CheckpointCompletionKind.Completed and observed.value.error ==
      CheckpointBankError.None
  assert worker.retry(ticket, observed.value.value).error ==
      CheckpointWorkerError.NotReady # A successful write may not masquerade as a safe stale-head retry.
  let completed = worker.collect(ticket)
  head = completed.value.value
  assert array[32, byte](head.root) == array[32, byte](root)
proc main() {.raises.} =
  ## Closed/foreign/default/cancelled/actual-success receipts never gain stale-refusal retry authority.
  for suffix in [".head", ".0", ".1"]:
    var path = Prefix & suffix
    discard posix.unlink(path.toCString()) # Test-owned reset precedes native startup.
  defer:
    for suffix in [".head", ".head.lock", ".0", ".1"]:
      var path = Prefix & suffix
      discard posix.unlink(path.toCString()) # Joined native owner retires before test-only stable inode removal.
  var worker = default(CheckpointWorker)
  defer: discard worker.close()
  assert worker.retry(default(CheckpointTicket), default(CheckpointHead)).error ==
      CheckpointWorkerError.Closed
  assert worker.peek(default(CheckpointTicket)).kind == CheckpointCompletionKind.Uninitialized
  assert worker.start(Prefix) == CheckpointBankError.None
  var initial = detached(1)
  let first = worker.stage(initial, CheckpointOperation.Bootstrap, default(CheckpointHead),
      ByteLimit(1000)).value
  assert worker.begin(first)
  worker.waitDone()
  let observed = worker.peek(first)
  assert observed.value.error == CheckpointBankError.None
  assert uint64(worker.peek(first).value.value.generation) ==
      0 # Repeated scalar receipts do not consume capacity or duplicate publication.
  assert worker.retry(first, observed.value.value).error == CheckpointWorkerError.NotReady
  var head = worker.collect(first).value.value
  var next = detached(2)
  let stale = newCheckpointHead(CheckpointGeneration(1), head.slot, head.root)
  let failed = worker.stage(next, CheckpointOperation.Advance, stale, ByteLimit(1000)).value
  assert worker.begin(failed)
  worker.waitDone()
  assert worker.peek(failed).value.error == CheckpointBankError.StaleHead
  assert worker.retry(default(CheckpointTicket), head).error == CheckpointWorkerError.NotReady
  assert worker.retry(failed, default(CheckpointHead)).error == CheckpointWorkerError.InvalidHead
  assert worker.peek(failed).value.error == CheckpointBankError.StaleHead # Refused retry preserves the old ticket and its exact receipt.
  let cancelled = worker.retry(failed, head).value
  assert worker.cancel(cancelled)
  assert worker.peek(cancelled).kind == CheckpointCompletionKind.Cancelled
  assert worker.retry(cancelled, head).error == CheckpointWorkerError.NotReady
  assert worker.collect(cancelled).kind == CheckpointCompletionKind.Cancelled
  var valid = detached(2)
  let actual = worker.stage(valid, CheckpointOperation.Advance, head, ByteLimit(1000)).value
  assert worker.begin(actual)
  worker.waitDone()
  head = worker.collect(actual).value.value
  cycle(worker, head)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(worker, head) # Host ticket/buffer release is measured separately from the I/O thread's allocator state.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_checkpoint_worker_retry", 1000, before, after)
  assert worker.close().retirementError == CheckpointBankError.None
  var bank = default(CheckpointBank)
  defer: discard bank.close()
  assert bank.openCheckpointBank(Prefix) == CheckpointBankError.None
  assert bank.restore(head.root, policy(), ByteLimit(1000)).error == CheckpointBankError.None
  assert uint64(bank.selectedHead().value.generation) == uint64(head.generation)
  assert bank.close() == CheckpointBankError.None
  echo "PASS checkpoint retry: retained sole buffers, fresh expected-head authority and no duplicate success"
try:
  main() # Thread/native startup errors cannot masquerade as typed safe retry refusals.
except:
  quit(2)
