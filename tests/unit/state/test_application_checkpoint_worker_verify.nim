# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_checkpoint_worker_verify_arc_release"}

## Verification owns all decoded maps on the native thread and returns only fixed context with explicit operation identity.
import std/[assertions, syncio]
import std/posix/posix
import ../../../src/app/[chain, checkpoint_worker, checkpoint_session, checkpoint_transfer,
    checkpoint_identity, checkpoint_file]
import ../../../src/state/store
import ../../../src/chain/genesis
import ../../../src/codec/bounded
import ../../../src/lib/atomic_file
import ../../support/[application_checkpoint_context, application_checkpoint_worker_context, arc_evidence]
const FileName = "application-checkpoint-worker-verify"
proc verified(worker: var ApplicationCheckpointWorker, expected: ApplicationCheckpointIdentity,
    limits: StateStoreLimits, limit: ByteLimit): ApplicationCheckpointCompletion =
  ## Every admitted request reports actual native verification, including exact typed refusals.
  let ticket = worker.stageVerification(expected, limits, limit).value
  assert worker.begin(ticket)
  worker.waitApplicationCheckpoint()
  result = worker.collect(ticket)
  assert result.kind == ApplicationCheckpointCompletionKind.Completed
  assert result.operation == ApplicationCheckpointOperation.Verify
proc cycle(worker: var ApplicationCheckpointWorker, expected: ApplicationCheckpointIdentity) =
  ## Only host ticket/fixed-receipt occupancy is observed; decoded graph release is covered by the verifier's native suite.
  let completed = verified(worker, expected, genesisStoreLimits(), ByteLimit(100000))
  assert completed.value.error == ApplicationCheckpointFileError.None
  assert sameApplicationCheckpoint(completed.value.value, expected)
proc main() {.raises.} =
  ## Publication and verification share capacity, generation authority, cancellation and joined receipt preservation.
  defer:
    for suffix in ["", ".lock"]:
      var path = FileName & suffix
      discard posix.unlink(path.toCString()) # Joined owners precede suite-only lock cleanup.
  let owner = checkpointFixture()
  let expected = captureApplicationCheckpointIdentity(owner).value
  assert saveApplicationCheckpoint(FileName, owner, ByteLimit(100000)).error ==
      ApplicationCheckpointFileError.None
  var worker = default(ApplicationCheckpointWorker)
  defer: discard worker.close()
  assert worker.stageVerification(expected, genesisStoreLimits(), ByteLimit(100000)).error ==
      ApplicationCheckpointWorkerError.Closed
  assert worker.start(FileName) == ApplicationCheckpointFileError.None
  assert worker.stageVerification(default(ApplicationCheckpointIdentity), genesisStoreLimits(),
      ByteLimit(100000)).error == ApplicationCheckpointWorkerError.InvalidContext
  let first = worker.stageVerification(expected, genesisStoreLimits(), ByteLimit(100000)).value
  var source = detachedApplicationCheckpoint()
  assert worker.stage(source, ByteLimit(100000)).error == ApplicationCheckpointWorkerError.Busy
  assert worker.begin(first)
  worker.waitApplicationCheckpoint()
  assert worker.peek(first).operation == ApplicationCheckpointOperation.Verify
  assert worker.stageVerification(expected, genesisStoreLimits(), ByteLimit(100000)).error ==
      ApplicationCheckpointWorkerError.Busy
  assert worker.collect(first).value.error == ApplicationCheckpointFileError.None
  let publish = worker.stage(source, ByteLimit(100000)).value
  assert not worker.begin(first) and worker.begin(publish)
  worker.waitApplicationCheckpoint()
  assert worker.collect(publish).operation == ApplicationCheckpointOperation.Publish
  let wrong = captureApplicationCheckpointIdentity(checkpointFixture(
      CheckpointFixtureVariant.Profile)).value
  assert verified(worker, wrong, default(StateStoreLimits), ByteLimit(100000)).value.error ==
      ApplicationCheckpointFileError.ContextMismatch
  assert verified(worker, expected, default(StateStoreLimits), ByteLimit(100000)).value.error ==
      ApplicationCheckpointFileError.LimitExceeded
  assert verified(worker, expected, genesisStoreLimits(), ByteLimit(0)).value.error ==
      ApplicationCheckpointFileError.LimitExceeded
  cycle(worker, expected)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(worker, expected) # No complete map or byte owner enters the fixed host receipt.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_checkpoint_worker_verify", 1000, before, after)
  let cancelled = worker.stageVerification(expected, genesisStoreLimits(), ByteLimit(100000)).value
  assert worker.cancel(cancelled)
  assert worker.collect(cancelled).kind == ApplicationCheckpointCompletionKind.Cancelled
  let joined = worker.stageVerification(expected, genesisStoreLimits(), ByteLimit(100000)).value
  assert worker.begin(joined)
  worker.waitApplicationCheckpoint()
  let shutdown = worker.close()
  assert shutdown.completion.operation == ApplicationCheckpointOperation.Verify
  assert shutdown.completion.value.error == ApplicationCheckpointFileError.None
  assert shutdown.retirementError == ApplicationCheckpointFileError.None
  var session = default(ApplicationCheckpointSession)
  defer: session.close()
  assert session.start(FileName) == ApplicationCheckpointFileError.None
  let pending = session.stageVerification(expected, genesisStoreLimits(), ByteLimit(100000)).value
  assert session.cancel(pending)
  session.close()
  assert session.takeShutdown().completion.kind == ApplicationCheckpointCompletionKind.Cancelled
  var path = FileName
  assert posix.unlink(path.toCString()) == 0 # All prior native owners are closed before removing the selected test file.
  assert worker.start(FileName) == ApplicationCheckpointFileError.None
  assert verified(worker, expected, genesisStoreLimits(), ByteLimit(100000)).value.error ==
      ApplicationCheckpointFileError.IoFailure
  assert worker.close().retirementError == ApplicationCheckpointFileError.None
  echo "PASS application checkpoint worker verification: independent context, local decoded maps and distinct typed operation receipts"
try:
  main() # Fixture/thread/native errors remain failures.
except:
  quit(2)
