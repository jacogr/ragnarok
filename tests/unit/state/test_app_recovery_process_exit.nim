# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Known staged/durable process exits after recovered execution preserve exact complete files and release child-only native locks.
import std/assertions
import std/syncio
import std/envvars
import std/posix/posix
import ../../../src/app/services as app_services
import ../../../src/app/chain as app_chain
import ../../../src/app/candidate as app_candidate
import ../../../src/app/checkpoint_identity as app_checkpoint_identity
import ../../../src/app/checkpoint_codec as app_checkpoint_codec
import ../../../src/app/checkpoint_recovery as app_checkpoint_recovery
import ../../../src/app/checkpoint_transfer as app_checkpoint_transfer
import ../../../src/app/checkpoint_worker as app_checkpoint_worker
import ../../../src/app/checkpoint_file as app_checkpoint_file
import ../../../src/app/checkpoint_writer as app_checkpoint_writer
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/header as codec_header
import ../../../src/lib/atomic_file as lib_atomic_file
import ../../support/app_candidate_context as candidate_context
import ../../support/state_accumulation_completion_context
import ../../support/app_recovery_execution
const ChainPath = "application-recovery-exit-chain"
const FileName = "application-recovery-exit"
proc childWork(fixture: RecoveryExecutionFixture, durable: bool) {.raises.} =
  ## Every worker/lock is created after fork; normal exit deliberately skips collection, join and all copied-parent destructors.
  var owner = default(Services)
  defer: owner.close() # Error unwinding retires only child-created owners; successful exitnow bypasses this cleanup.
  startRecoveredExecution(owner, fixture, ChainPath, candidate_context.policy())
  let queued = owner.enqueueCandidate(candidate_context.candidateBlock(fixture.origin), [],
    candidate_context.preparationLimits(), completionLimits().composition)
  assert queued.error == ApplicationCandidateError.None
  owner.tick(0)
  assert owner.takeAccumulation().error == ApplicationChainError.None
  var prepared = owner.prepareCheckpoint(ByteLimit(1000000))
  assert owner.startCheckpointExport(FileName) == ApplicationCheckpointFileError.None
  let ticket = owner.stageCheckpointExport(prepared, ByteLimit(1000000)).value
  if durable:
    assert owner.beginCheckpointExport(ticket)
    waitRecoveredExport(owner)
    let actual = owner.peekCheckpointExport(ticket)
    assert actual.kind == ApplicationCheckpointCompletionKind.Completed
    assert actual.operation == ApplicationCheckpointOperation.Publish
    assert actual.value.error == ApplicationCheckpointFileError.None # Actual durable Done precedes abrupt exit, not a guessed scheduling delay.
  else:
    assert owner.checkpointExportPhase == ApplicationCheckpointWorkerPhase.Staged # No I/O dispatch has been granted.
  posix.exitnow(0)
proc scenario(fixture: RecoveryExecutionFixture, next: ApplicationCheckpointIdentity,
    nextHeader, nextBytes: seq[byte], durable: bool) {.raises.} =
  ## Parent owns no native worker or cooperative lock at fork; independent trusted context determines post-exit recovery.
  assert replaceAtomicFile(FileName, fixture.envelope, ByteLimit(1000000)) == AtomicFileError.None
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    try:
      childWork(fixture, durable) # Child-only complete-map execution/publication cannot destroy copied parent owners.
    except:
      posix.exitnow(3) # Any native/fixture error is a failed boundary witness.
    posix.exitnow(4) # Returning without observing a selected boundary is never success.
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var status = 0.cint
      discard posix.waitpid(child, status, 0) # Every failed parent path still reaps its child.
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child
  reaped = true
  assert WIFEXITED(status) and WEXITSTATUS(status) == 0
  let expected = if durable: next else: fixture.expected
  let sealed = if durable: nextHeader else: fixture.sealed
  let bytes = if durable: nextBytes else: fixture.envelope
  assert readBoundedFile(FileName, ByteLimit(1000000)).value == bytes
  var writer = default(ApplicationCheckpointWriter)
  defer: discard writer.close()
  assert writer.openApplicationCheckpointWriter(FileName) == ApplicationCheckpointFileError.None
  assert writer.verify(expected, candidate_context.policy(), ByteLimit(1000000)).error ==
      ApplicationCheckpointFileError.None
  assert writer.close() == ApplicationCheckpointFileError.None # A fresh parent lock proves process retirement released the child-only lock.
  let restored = loadRecoveryCheckpoint(FileName, sealed, expected, candidate_context.policy(),
      ByteLimit(1000000))
  assert restored.error == ApplicationRecoveryError.None
  assert sameApplicationCheckpoint(captureApplicationCheckpointIdentity(restored.value).value, expected)
  assert restored.value.chainView.retainedCount == 1 and
      restored.value.chainView.finalizedBlock.error != GenesisError.None
  let other = if durable: fixture.expected else: next
  let otherHeader = if durable: fixture.sealed else: nextHeader
  let refused = loadRecoveryCheckpoint(FileName, otherHeader, other, candidate_context.policy(),
      ByteLimit(1000000))
  assert refused.fileFailure.error == ApplicationCheckpointFileError.ContextMismatch
  assert readBoundedFile(FileName, ByteLimit(1000000)).value ==
      bytes # Failed trust never rewrites the file selected at the observed process boundary.
proc main() {.raises.} =
  ## The independently executed direct child supplies expected trust; exported file metadata never authenticates itself.
  defer:
    for selected in [ChainPath, FileName, FileName & ".lock"]:
      var path = selected
      discard posix.unlink(path.toCString()) # All child processes and parent lock probes retire before cleanup.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw:
    report[index] = byte(octet) # Detach initialized pinned bytes before constructing the genuine signed fixture.
  let fixture = recoveryFixture(decodeOwnedReport(report, 2).value)
  var reference = candidate_context.initialized(fixture.origin)
  let prepared = reference.prepareCandidate(candidate_context.candidateBlock(fixture.origin), [],
      candidate_context.preparationLimits())
  assert prepared.error == ApplicationCandidateError.None
  assert reference.applyAccumulation(prepared.value, completionLimits().composition).error ==
      ApplicationChainError.None
  let next = captureApplicationCheckpointIdentity(reference).value
  let nextBytes = encodeApplicationCheckpoint(reference, ByteLimit(1000000)).value
  let header = reference.chainView.bestBlock.value.header
  var nextHeader = newSeq[byte](header.headerInfo.value.consumed)
  assert encodeOwnedHeader(header, nextHeader).error == HeaderError.None
  scenario(fixture, next, nextHeader, nextBytes, false)
  scenario(fixture, next, nextHeader, nextBytes, true)
  echo "PASS application recovery process exit: exact staged/durable selection, independent trust and child lock retirement"
try:
  main() # Known process boundaries do not claim power-loss or cross-process ARC evidence.
except:
  quit(2)
