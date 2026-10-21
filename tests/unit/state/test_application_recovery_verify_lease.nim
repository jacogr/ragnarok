# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Read-only verification after recovery preserves distinct actual outcomes while canonical execution exclusion remains held.
import std/[assertions, syncio, envvars]
import std/posix/posix
import ../../../src/app/[services, chain, block_input, preparation_worker, checkpoint_identity,
  checkpoint_transfer, checkpoint_worker, checkpoint_file]
import ../../../src/rpc/server
import ../../../src/chain/genesis
import ../../../src/codec/[bounded, report_owned]
import ../../../src/lib/atomic_file
import ../../support/application_candidate_context as candidate_context
import ../../support/[application_recovery_execution, application_checkpoint_context]
const ChainPath = "application-recovery-verify-chain"
const FileName = "application-recovery-verify"
proc main() {.raises.} =
  ## Verification never substitutes for publication, adopts its temporary map or relaxes another native worker's lease.
  defer:
    for selected in [ChainPath, FileName, FileName & ".lock"]:
      var path = selected
      discard posix.unlink(path.toCString()) # Both native owners must retire before path cleanup.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw:
    report[index] = byte(octet) # Detach initialized pinned fixture bytes before owned decoding.
  let fixture = recoveryFixture(decodeOwnedReport(report, 2).value)
  let wrong = captureApplicationCheckpointIdentity(checkpointFixture()).value
  var input = default(BlockInput)
  var owner = default(Services)
  defer: owner.close()
  startRecoveredExecution(owner, fixture, ChainPath, candidate_context.policy())
  let expected = owner.checkpointIdentity.value
  assert not sameApplicationCheckpoint(expected, wrong)
  var prepared = owner.prepareCheckpoint(ByteLimit(1000000))
  assert owner.startCheckpointExport(FileName) == ApplicationCheckpointFileError.None
  let publication = owner.stageCheckpointExport(prepared, ByteLimit(1000000)).value
  assert owner.beginCheckpointExport(publication)
  waitRecoveredExport(owner)
  assert owner.collectCheckpointExport(publication).operation ==
      ApplicationCheckpointOperation.Publish
  let original = readBoundedFile(FileName, ByteLimit(1000000)).value
  let id = receiveRecoveryInput(owner, input, [255'u8])
  assert owner.beginPreparation(input, id).error == PreparationError.None
  assert owner.preparationActive and owner.rpc.chainPaused
  let absent = default(ApplicationCheckpointIdentity)
  let refused = owner.stageCheckpointVerification(absent, genesisStoreLimits(), ByteLimit(1000000))
  assert refused.error == ApplicationCheckpointWorkerError.InvalidContext
  let mismatch = owner.stageCheckpointVerification(wrong, genesisStoreLimits(), ByteLimit(1000000)).value
  assert owner.beginCheckpointExport(mismatch)
  waitRecoveredExport(owner)
  let failed = owner.collectCheckpointExport(mismatch)
  assert failed.kind == ApplicationCheckpointCompletionKind.Completed
  assert failed.operation == ApplicationCheckpointOperation.Verify
  assert failed.value.error == ApplicationCheckpointFileError.ContextMismatch
  assert owner.preparationActive and owner.rpc.chainPaused
  let ticket = owner.stageCheckpointVerification(expected, genesisStoreLimits(), ByteLimit(1000000)).value
  assert owner.beginCheckpointExport(ticket)
  waitRecoveredExport(owner)
  let observed = owner.peekCheckpointExport(ticket)
  assert observed.kind == ApplicationCheckpointCompletionKind.Completed
  assert observed.operation == ApplicationCheckpointOperation.Verify
  assert observed.value.error == ApplicationCheckpointFileError.None
  assert sameApplicationCheckpoint(observed.value.value, expected)
  assert owner.preparationActive and owner.rpc.chainPaused
  let busy = owner.stageCheckpointVerification(expected, genesisStoreLimits(), ByteLimit(1000000))
  assert busy.error == ApplicationCheckpointWorkerError.Busy # Unacknowledged Done still owns the shared I/O slot.
  owner.close()
  owner.close()
  discard input.cancel(id) # Joined shutdown ends raw/canonical borrowing before host retirement.
  assert not owner.preparationActive and not owner.rpc.chainPaused
  assert owner.checkpointShutdownPending
  let shutdown = owner.takeCheckpointShutdown()
  assert shutdown.retirementError == ApplicationCheckpointFileError.None
  assert shutdown.completion.operation == ApplicationCheckpointOperation.Verify
  assert sameApplicationCheckpoint(shutdown.completion.value.value, expected)
  assert owner.checkpointIdentity.error == ApplicationCheckpointIdentityError.MissingHead
  assert readBoundedFile(FileName, ByteLimit(1000000)).value == original
  assert verifyApplicationCheckpoint(FileName, expected, genesisStoreLimits(), ByteLimit(
      1000000)).error == ApplicationCheckpointFileError.None
  assert not owner.beginCheckpointExport(ticket)
  echo "PASS application recovery verification lease: independent trust, precise refusal, read-only bytes and distinct joined receipts"
try:
  main() # Native/context failures cannot yield a publication receipt or installed recovered map.
except:
  quit(2)
