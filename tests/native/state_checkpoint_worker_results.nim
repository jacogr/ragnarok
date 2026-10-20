# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/failed admissions and unstarted shutdown cannot fabricate committed worker receipts.

import std/[assertions, cmdline, monotimes, times, syncio]
import std/posix/posix
import ../../src/state/[checkpoint_worker, checkpoint_bank, checkpoint_head, checkpoint_transfer,
    checkpoint, store]
import ../../src/codec/[state_trie, bounded]

proc extractCompletion(completion: CheckpointCompletion) =
  ## Preserve a runtime misuse witness after callers verify its cancellation kind; the accessor still enforces its own contract.
  discard completion.value
proc prepared(): PreparedCheckpoint =
  ## A real initialized empty complete map supplies a small valid I/O buffer.
  let limits = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(0), perValue: ByteLimit(0),
    totalValueBytes: ByteLimit(0), nodes: TrieNodeLimit(0)), writes: ElementLimit(0),
        writeValueBytes: ByteLimit(0))
  prepareFullCheckpoint(newStateStore([], limits).value.snapshot.value, ByteLimit(1000))
proc forgotten() {.raises.} =
  ## Composite destruction cannot silently abandon a thread and a live bank descriptor.
  var worker = default(CheckpointWorker)
  assert worker.start("build/checkpoint-worker-unclosed") == CheckpointBankError.None
proc main() {.raises.} =
  ## The genuine staged/cancelled close path retires every native resource before the guarded extraction.
  let mode = paramStr(1)
  if mode == "unclosed":
    forgotten() # Checked destruction must reject a live native owner.
  elif mode == "moved":
    var worker = default(CheckpointWorker)
    assert worker.start("build/checkpoint-worker-moved") == CheckpointBankError.None
    var transferred = move(worker)
    discard transferred.close() # The public move hook must reject relocation while a thread still borrows the original owner address.
  elif mode == "admission":
    let absent = default(CheckpointAdmission)
    discard absent.value # Default admission grants no ticket.
  elif mode == "completion":
    let absent = default(CheckpointCompletion)
    extractCompletion(absent) # Default completion has no bank outcome.
  else:
    for suffix in [".head", ".0"]:
      var path = "build/checkpoint-worker-results" & suffix
      discard posix.unlink(path.toCString()) # Test-only reset precedes native owner startup.
    defer:
      for suffix in [".head", ".head.lock", ".0"]:
        var path = "build/checkpoint-worker-results" & suffix
        discard posix.unlink(path.toCString()) # Test-only cleanup follows joined worker retirement below.
    var worker = default(CheckpointWorker)
    defer: discard worker.close()
    assert worker.start("build/checkpoint-worker-results") == CheckpointBankError.None
    var source = prepared()
    let admitted = worker.stage(source, CheckpointOperation.Bootstrap, default(CheckpointHead),
        ByteLimit(1000))
    assert admitted.error == CheckpointWorkerError.None and worker.phase ==
        CheckpointWorkerPhase.Staged
    let ticket = admitted.value
    if mode == "cancelled":
      let shutdown = worker.close()
      assert shutdown.retirementError == CheckpointBankError.None
      assert shutdown.completion.kind == CheckpointCompletionKind.Cancelled
      extractCompletion(shutdown.completion) # Joined unstarted work cannot expose a fabricated bank result.
    else:
      assert mode == "positive" and source.error == CheckpointError.Uninitialized
      assert worker.begin(ticket)
      let started = getMonoTime()
      while worker.phase != CheckpointWorkerPhase.Done:
        assert (getMonoTime() - started).inSeconds < 20, "native positive completion deadline"
        var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
        var remaining = default(Timespec)
        discard nanosleep(requested, remaining) # Yield only in this real positive control's bounded test wait.
      let completed = worker.collect(ticket)
      assert completed.kind == CheckpointCompletionKind.Completed
      assert completed.value.error == CheckpointBankError.None and
          completed.value.value.ready # The positive path must exercise both guarded extraction layers after actual I/O.
      extractCompletion(completed) # The same opaque runtime extraction must succeed for genuine completed work.
      assert worker.close().retirementError == CheckpointBankError.None

try:
  main() # Raised thread-startup failures are distinct from the native assertion/contract exit under test.
except:
  quit(2)
