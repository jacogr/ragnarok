# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_checkpoint_worker_verify_arc_release"}

## Worker verification destroys complete decoded state before publishing fixed-size trusted recovery metadata.

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

const Prefix = "state-checkpoint-worker-verify"
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
proc verify(worker: var CheckpointWorker, root: StateRoot, limits: StateStoreLimits,
    limit: ByteLimit): CheckpointCompletion =
  ## Only independent scalar trust and budgets cross into the native verifier.
  let ticket = worker.stageVerification(root, limits, limit).value
  assert worker.begin(ticket)
  worker.waitDone()
  assert worker.stageHead().error == CheckpointWorkerError.Busy
  assert worker.retry(ticket, default(CheckpointHead)).error == CheckpointWorkerError.NotReady
  worker.collect(ticket)
proc cycle(worker: var CheckpointWorker, expected: CheckpointHead) =
  ## Matching root/slot/generation are fixed scalar receipts; no worker-created complete map is shared.
  let result = verify(worker, expected.root, policy(), ByteLimit(1000))
  assert result.kind == CheckpointCompletionKind.Completed and result.value.error ==
      CheckpointBankError.None
  let head = result.value.value
  assert uint64(head.generation) == uint64(expected.generation) and head.slot == expected.slot
  assert array[32, byte](head.root) == array[32, byte](expected.root)
proc main() {.raises.} =
  ## Untrusted heads, malformed/missing selected bytes and independent resource ceilings remain distinct typed failures.
  for suffix in [".head", ".0", ".1"]:
    var path = Prefix & suffix
    discard posix.unlink(path.toCString()) # Isolated test namespace is cleared before startup.
  defer:
    for suffix in [".head", ".head.lock", ".0", ".1"]:
      var path = Prefix & suffix
      discard posix.unlink(path.toCString()) # Joined workers retire before test-only lock inode cleanup.
  var worker = default(CheckpointWorker)
  defer: discard worker.close()
  assert worker.stageVerification(default(StateRoot), policy(), ByteLimit(1000)).error ==
      CheckpointWorkerError.Closed
  assert worker.start(Prefix) == CheckpointBankError.None
  assert verify(worker, default(StateRoot), policy(), ByteLimit(1000)).value.error ==
      CheckpointBankError.IoFailure
  var initial = detached(8)
  let first = worker.stage(initial, CheckpointOperation.Bootstrap, default(CheckpointHead),
      ByteLimit(1000)).value
  assert worker.begin(first)
  worker.waitDone()
  let head = worker.collect(first).value.value
  let original = readBoundedFile(Prefix & ".0", ByteLimit(1000)).value
  assert verify(worker, default(StateRoot), policy(), ByteLimit(1000)).value.error ==
      CheckpointBankError.RootMismatch
  assert verify(worker, head.root, policy(), ByteLimit(0)).value.error ==
      CheckpointBankError.LimitExceeded
  var narrow = policy()
  narrow.trie.items = ElementLimit(0)
  let refused = verify(worker, head.root, narrow, ByteLimit(1000))
  assert refused.value.error == CheckpointBankError.InvalidCheckpoint and
      refused.value.checkpointError == CheckpointError.LimitExceeded
  cycle(worker, head)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(worker, head) # This measures host receipts/tickets only; temporary map allocation is owned by the native thread.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_checkpoint_worker_verify", 1000, before, after)
  var corrupt = original
  corrupt[0] = corrupt[0] xor 1
  assert replaceAtomicFile(Prefix & ".0", corrupt, ByteLimit(1000)) == AtomicFileError.None
  let invalid = verify(worker, head.root, policy(), ByteLimit(1000))
  assert invalid.value.error == CheckpointBankError.InvalidCheckpoint and
      invalid.value.checkpointError == CheckpointError.InvalidFormat
  assert replaceAtomicFile(Prefix & ".0", original, ByteLimit(1000)) == AtomicFileError.None
  let cancelled = worker.stageVerification(head.root, policy(), ByteLimit(1000)).value
  assert worker.cancel(cancelled) and worker.collect(cancelled).kind ==
      CheckpointCompletionKind.Cancelled
  let done = worker.stageVerification(head.root, policy(), ByteLimit(1000)).value
  assert worker.begin(done)
  worker.waitDone()
  let closed = worker.close()
  assert closed.retirementError == CheckpointBankError.None
  assert closed.completion.kind == CheckpointCompletionKind.Completed
  assert closed.completion.value.error == CheckpointBankError.None
  assert readBoundedFile(Prefix & ".0", ByteLimit(1000)).value == original
  echo "PASS checkpoint worker verification: independent trust, thread-local complete maps and scalar receipts"
try:
  main() # Native startup failures cannot masquerade as verification refusals.
except:
  quit(2)
