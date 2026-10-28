# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Recovered canonical maps export detached bytes during a separate execution lease without mixing publication or shutdown authority.
import std/assertions
import std/syncio
import std/envvars
import std/posix/posix
import ../../../src/app/services as app_services
import ../../../src/app/block_input as app_block_input
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/checkpoint_identity as app_checkpoint_identity
import ../../../src/app/checkpoint_transfer as app_checkpoint_transfer
import ../../../src/app/checkpoint_worker as app_checkpoint_worker
import ../../../src/app/checkpoint_file as app_checkpoint_file
import ../../../src/app/checkpoint_codec as app_checkpoint_codec
import ../../../src/rpc/server as rpc_server
import ../../../src/chain/genesis as chain_genesis
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/lib/atomic_file as lib_atomic_file
import ../../support/app_candidate_context as candidate_context
import ../../support/app_recovery_execution
const ChainPath = "application-recovery-export-chain"
const FileName = "application-recovery-export"
proc scenario(fixture: RecoveryExecutionFixture, acknowledge: bool) {.raises.} =
  ## Only fixed identity and sole prepared bytes survive canonical capture; no map is shared with the I/O worker.
  var input = default(BlockInput)
  var owner = default(Services)
  defer: owner.close() # Both workers join before borrowed raw input retires.
  startRecoveredExecution(owner, fixture, ChainPath, candidate_context.policy())
  let expected = owner.checkpointIdentity.value
  var prepared = owner.prepareCheckpoint(ByteLimit(1000000))
  assert prepared.error == ApplicationCheckpointError.None
  assert owner.startCheckpointExport(FileName) == ApplicationCheckpointFileError.None
  let id = receiveRecoveryInput(owner, input, [255'u8])
  assert owner.beginPreparation(input, id).error == PreparationError.None
  assert owner.preparationActive and owner.rpc.chainPaused
  let ticket = owner.stageCheckpointExport(prepared, ByteLimit(1000000)).value
  assert prepared.error == ApplicationCheckpointError.Uninitialized # Host source loses sole-byte publication authority after staging.
  assert owner.beginCheckpointExport(ticket)
  waitRecoveredExport(owner)
  assert owner.preparationActive and owner.rpc.chainPaused
  let observed = owner.peekCheckpointExport(ticket)
  assert observed.kind == ApplicationCheckpointCompletionKind.Completed
  assert observed.operation == ApplicationCheckpointOperation.Publish
  assert observed.value.error == ApplicationCheckpointFileError.None
  assert sameApplicationCheckpoint(observed.value.value, expected)
  if acknowledge:
    assert owner.collectCheckpointExport(ticket).kind ==
        ApplicationCheckpointCompletionKind.Completed # Collection releases only the I/O slot.
  else:
    assert owner.peekCheckpointExport(ticket).operation ==
        ApplicationCheckpointOperation.Publish # Observation retains actual receipt authority until joined acknowledgement.
  assert owner.preparationActive and owner.rpc.chainPaused
  owner.close()
  owner.close()
  discard input.cancel(id) # Joined close has retired every raw/canonical native borrow.
  assert not owner.preparationActive and not owner.rpc.chainPaused
  assert owner.checkpointShutdownPending == (not acknowledge)
  assert readBoundedFile(FileName, ByteLimit(1000000)).value == fixture.envelope
  assert verifyApplicationCheckpoint(FileName, expected, genesisStoreLimits(), ByteLimit(
      1000000)).error == ApplicationCheckpointFileError.None
  startRecoveredExecution(owner, fixture, ChainPath, candidate_context.policy())
  if not acknowledge:
    assert owner.startCheckpointExport(FileName) == ApplicationCheckpointFileError.Busy
    let shutdown = owner.takeCheckpointShutdown()
    assert shutdown.retirementError == ApplicationCheckpointFileError.None
    assert shutdown.completion.operation == ApplicationCheckpointOperation.Publish
    assert sameApplicationCheckpoint(shutdown.completion.value.value,
        expected) # Reimport cannot overwrite or relabel an earlier actual joined outcome.
  assert owner.startCheckpointExport(FileName) == ApplicationCheckpointFileError.None
  assert not owner.beginCheckpointExport(ticket)
  owner.close()
  assert not owner.checkpointShutdownPending # Clean idle restart cannot fabricate a duplicate durable publication receipt.
proc main() {.raises.} =
  ## Collected and joined-only completion cross actual restored ownership and both native worker lifetimes.
  defer:
    for selected in [ChainPath, FileName, FileName & ".lock"]:
      var path = selected
      discard posix.unlink(path.toCString()) # All native owners retire before test-only path cleanup.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw:
    report[index] = byte(octet) # Preserve explicit initialized fixture ownership.
  let fixture = recoveryFixture(decodeOwnedReport(report, 2).value)
  scenario(fixture, true)
  scenario(fixture, false)
  echo "PASS application recovery export lease: exact detached bytes, independent gates and retained publication receipts"
try:
  main() # Native errors cannot be converted into successful export or lease retirement.
except:
  quit(2)
