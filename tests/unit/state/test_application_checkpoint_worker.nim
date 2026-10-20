# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_checkpoint_worker_arc_release"}

## Native whole-envelope publication owns one slot through acknowledgement and preserves actual joined outcomes.
import std/[assertions, syncio]
import std/posix/posix
import ../../../src/app/[checkpoint_worker, checkpoint_transfer, checkpoint_codec, checkpoint_file, checkpoint_identity]
import ../../../src/chain/genesis
import ../../../src/codec/bounded
import ../../support/[application_checkpoint_worker_context, application_checkpoint_context, arc_evidence]
const FileName = "application-checkpoint-worker"
proc cycle(worker: var ApplicationCheckpointWorker) {.raises.} =
  ## Host-created buffers return to their allocator only after worker-local file activations retire.
  var source = detachedApplicationCheckpoint()
  let expected = source.identity
  let admitted = worker.stage(source, ByteLimit(100000))
  assert admitted.error == ApplicationCheckpointWorkerError.None
  assert source.error == ApplicationCheckpointError.Uninitialized
  assert worker.begin(admitted.value)
  worker.waitApplicationCheckpoint()
  let completed = worker.collect(admitted.value)
  assert completed.kind == ApplicationCheckpointCompletionKind.Completed
  assert completed.value.error == ApplicationCheckpointFileError.None
  assert sameApplicationCheckpoint(completed.value.value, expected)
proc main() {.raises.} =
  ## Admission refusal preserves caller ownership; stale and foreign namespaces never grant another request's receipt.
  defer:
    for suffix in ["", ".lock", "-foreign", "-foreign.lock"]:
      var path = FileName & suffix
      discard posix.unlink(path.toCString()) # Joined/closed owners retire before test-only namespace cleanup.
  var inactive = default(ApplicationCheckpointWorker)
  var relocated = move(inactive)
  assert relocated.close().retirementError == ApplicationCheckpointFileError.None
  var worker = default(ApplicationCheckpointWorker)
  defer: discard worker.close()
  var foreign = default(ApplicationCheckpointWorker)
  defer: discard foreign.close()
  var source = detachedApplicationCheckpoint()
  let expected = source.identity
  assert worker.stage(source, ByteLimit(100000)).error == ApplicationCheckpointWorkerError.Closed
  assert source.error == ApplicationCheckpointError.None
  assert worker.start("") == ApplicationCheckpointFileError.InvalidPath
  assert worker.start(FileName) == ApplicationCheckpointFileError.None
  assert worker.start(FileName) == ApplicationCheckpointFileError.Busy
  assert foreign.start(FileName) == ApplicationCheckpointFileError.Busy
  assert foreign.start(FileName & "-foreign") == ApplicationCheckpointFileError.None
  var empty = default(PreparedApplicationCheckpoint)
  assert worker.stage(empty, ByteLimit(100000)).error == ApplicationCheckpointWorkerError.NotReady
  assert worker.stage(source, ByteLimit(0)).error == ApplicationCheckpointWorkerError.LimitExceeded
  assert source.error == ApplicationCheckpointError.None
  let first = worker.stage(source, ByteLimit(100000)).value
  assert source.error == ApplicationCheckpointError.Uninitialized
  assert worker.phase == ApplicationCheckpointWorkerPhase.Staged
  var otherSource = detachedApplicationCheckpoint(CheckpointFixtureVariant.Profile)
  let other = foreign.stage(otherSource, ByteLimit(100000)).value
  assert not worker.begin(other) and not foreign.begin(first)
  assert worker.collect(first).kind == ApplicationCheckpointCompletionKind.Uninitialized
  var busy = detachedApplicationCheckpoint()
  assert worker.stage(busy, ByteLimit(100000)).error == ApplicationCheckpointWorkerError.Busy
  assert busy.error == ApplicationCheckpointError.None
  assert worker.begin(first) and not worker.begin(first)
  worker.waitApplicationCheckpoint()
  assert worker.stage(busy, ByteLimit(100000)).error == ApplicationCheckpointWorkerError.Busy
  let completed = worker.collect(first)
  assert completed.kind == ApplicationCheckpointCompletionKind.Completed
  assert sameApplicationCheckpoint(completed.value.value, expected)
  assert loadApplicationCheckpoint(FileName, expected, genesisStoreLimits(), ByteLimit(
      100000)).error == ApplicationCheckpointFileError.None
  assert worker.collect(first).kind == ApplicationCheckpointCompletionKind.Uninitialized
  let cancelled = foreign.close()
  assert cancelled.completion.kind == ApplicationCheckpointCompletionKind.Cancelled
  assert cancelled.retirementError == ApplicationCheckpointFileError.None
  cycle(worker)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(worker) # Occupancy covers host sole-buffer/ticket retirement, not the worker-thread allocator.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_checkpoint_worker", 1000, before, after)
  assert worker.close().retirementError == ApplicationCheckpointFileError.None
  assert worker.start(FileName) == ApplicationCheckpointFileError.None
  var changed = detachedApplicationCheckpoint(CheckpointFixtureVariant.Header)
  let changedIdentity = changed.identity
  let later = worker.stage(changed, ByteLimit(100000)).value
  assert not worker.begin(first) and worker.collect(first).kind ==
      ApplicationCheckpointCompletionKind.Uninitialized
  assert worker.begin(later)
  worker.waitApplicationCheckpoint()
  let joined = worker.close()
  assert joined.retirementError == ApplicationCheckpointFileError.None
  assert joined.completion.kind == ApplicationCheckpointCompletionKind.Completed
  assert sameApplicationCheckpoint(joined.completion.value.value, changedIdentity)
  assert loadApplicationCheckpoint(FileName, changedIdentity, genesisStoreLimits(), ByteLimit(
      100000)).error == ApplicationCheckpointFileError.None
  echo "PASS application checkpoint worker: sole bytes, bounded admission, ticket isolation and joined real publication"
try:
  main() # Thread/native fixture setup failures remain nonzero.
except:
  quit(2)
