# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_checkpoint_worker_cancel_arc_release"}

## Staged-only cancellation cannot overwrite an actual publication and keeps backpressure until explicit acknowledgement.
import std/assertions
import std/syncio
import std/posix/posix
import ../../../src/app/checkpoint_worker as app_checkpoint_worker
import ../../../src/app/checkpoint_transfer as app_checkpoint_transfer
import ../../../src/app/checkpoint_codec as app_checkpoint_codec
import ../../../src/app/checkpoint_file as app_checkpoint_file
import ../../../src/app/checkpoint_identity as app_checkpoint_identity
import ../../../src/chain/genesis as chain_genesis
import ../../../src/codec/bounded as codec_bounded
import ../../support/app_checkpoint_worker_context
import ../../support/app_checkpoint_context
import ../../support/testing_arc_evidence
const FileName = "application-checkpoint-worker-cancel"
proc cycle(worker: var ApplicationCheckpointWorker) {.raises.} =
  ## Cancelled buffers retire on their allocating host without ever entering native I/O.
  var source = detachedApplicationCheckpoint()
  let ticket = worker.stage(source, ByteLimit(100000)).value
  assert worker.cancel(ticket) and not worker.cancel(ticket)
  assert worker.peek(ticket).kind == ApplicationCheckpointCompletionKind.Cancelled
  assert worker.collect(ticket).kind == ApplicationCheckpointCompletionKind.Cancelled
  assert worker.peek(ticket).kind == ApplicationCheckpointCompletionKind.Uninitialized
proc main() {.raises.} =
  ## Wrong/default/stale tickets cannot cancel or observe another request, and Done retains capacity.
  defer:
    for suffix in ["", ".lock", "-foreign", "-foreign.lock"]:
      var path = FileName & suffix
      discard posix.unlink(path.toCString()) # All native owners join before suite-only lock inode cleanup.
  var worker = default(ApplicationCheckpointWorker)
  defer: discard worker.close()
  var foreign = default(ApplicationCheckpointWorker)
  defer: discard foreign.close()
  assert not worker.cancel(default(ApplicationCheckpointTicket))
  assert worker.peek(default(ApplicationCheckpointTicket)).kind ==
      ApplicationCheckpointCompletionKind.Uninitialized
  assert worker.start(FileName) == ApplicationCheckpointFileError.None
  assert foreign.start(FileName & "-foreign") == ApplicationCheckpointFileError.None
  var first = detachedApplicationCheckpoint()
  let ticket = worker.stage(first, ByteLimit(100000)).value
  var otherSource = detachedApplicationCheckpoint()
  let other = foreign.stage(otherSource, ByteLimit(100000)).value
  assert not worker.cancel(other) and not foreign.cancel(ticket)
  assert worker.peek(other).kind == ApplicationCheckpointCompletionKind.Uninitialized
  assert worker.peek(ticket).kind == ApplicationCheckpointCompletionKind.Uninitialized
  assert worker.cancel(ticket) and not worker.begin(ticket)
  var busy = detachedApplicationCheckpoint()
  assert worker.stage(busy, ByteLimit(100000)).error == ApplicationCheckpointWorkerError.Busy
  assert busy.error == ApplicationCheckpointError.None
  assert worker.peek(ticket).kind == ApplicationCheckpointCompletionKind.Cancelled
  assert worker.collect(ticket).kind == ApplicationCheckpointCompletionKind.Cancelled
  assert not worker.cancel(ticket)
  cycle(worker)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(worker) # This witnesses host buffer/ticket release; no thread allocator claim is made.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("app_checkpoint_worker_cancel", 1000, before, after)
  let expected = busy.identity
  let running = worker.stage(busy, ByteLimit(100000)).value
  assert worker.begin(running)
  assert not worker.cancel(running) # Dispatch immediately excludes cancellation regardless of scheduler timing.
  worker.waitApplicationCheckpoint()
  assert not worker.cancel(running)
  let observed = worker.peek(running)
  assert observed.kind == ApplicationCheckpointCompletionKind.Completed
  assert sameApplicationCheckpoint(observed.value.value, expected)
  var blocked = detachedApplicationCheckpoint()
  assert worker.stage(blocked, ByteLimit(100000)).error == ApplicationCheckpointWorkerError.Busy
  assert worker.collect(running).kind == ApplicationCheckpointCompletionKind.Completed
  assert loadApplicationCheckpoint(FileName, expected, genesisStoreLimits(), ByteLimit(
      100000)).error == ApplicationCheckpointFileError.None
  assert foreign.cancel(other)
  let joined = foreign.close()
  assert joined.completion.kind == ApplicationCheckpointCompletionKind.Cancelled
  assert joined.retirementError == ApplicationCheckpointFileError.None
  assert foreign.start(FileName & "-foreign") == ApplicationCheckpointFileError.None
  assert not foreign.cancel(other) and foreign.peek(other).kind ==
      ApplicationCheckpointCompletionKind.Uninitialized
  assert foreign.close().retirementError == ApplicationCheckpointFileError.None
  assert worker.close().retirementError == ApplicationCheckpointFileError.None
  echo "PASS application checkpoint cancellation: staged-only authority, retained capacity, exact peek and joined cancellation"
try:
  main() # Setup failures remain distinguishable from real cancellation behavior.
except:
  quit(2)
