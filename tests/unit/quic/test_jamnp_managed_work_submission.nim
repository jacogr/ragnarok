# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_managed_work_submission_arc_release"}

## Real managed work turns keep canonical ARC owners private through authorization, body waits and unrelated Done leases.
import std/[assertions, syncio, monotimes, times]
import ../../../src/app/[services, options]
import ../../../src/app/proof/[worker, work_submission as work_jobs]
import ../../../src/jamnp-s/[work_submission, read_stream]
import ../../../src/jamnp-s/work_duty
import ../../../src/state/input_refinement
import "../../../src/state/import/inputs" as import_inputs
import ../../../src/codec/bounded
import ../../../src/codec/work/package as work_package
import ../../../src/chain/genesis
import ../../support/[jamnp_work_fixture, jamnp_read_validation_context, pvm_input_refinement,
    pvm_import_inputs, arc_evidence]

proc waitDone(services: var Services) =
  ## A bounded deadline observes only worker scalar state; Done continues to occupy the shared graph lease.
  let deadline = getMonoTime()+initDuration(seconds = 8)
  while services.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "managed work CPU deadline"
proc checkExecution(services: Services, token: WorkSessionToken) =
  ## Every extracted source-bearing alias retires before another CPU turn can be admitted.
  let outcome = services.workSubmissionOutcome(token)
  assert outcome.kind == WorkJobResultKind.Refined
  assert outcome.execution.inputRefinementSource.value.importInputsInfo.value.entries == 2
proc managed(f: WorkFixture) {.raises.} =
  ## Actual Services owns session artifacts; native frame simulation receives only opaque control tokens and copied geometry.
  writeFile("managed-work-chain.json", f.workChainText)
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "managed-work-chain.json"], settings)
  var services = default(Services)
  defer: services.close()
  let header = f.workHeader
  assert services.beginWorkSubmission(header, f.limits, executionLimits()).error ==
      StateProofAdmissionError.Closed
  assert services.start(settings, "managed work")
  let request = readStateRequest(services.chainView.bestBlock.value.blockHash)
  let started = services.beginWorkSubmission(header, f.limits, executionLimits())
  assert started.error == StateProofAdmissionError.None
  let token = started.value
  assert services.workSessionPhase(token) == WorkSessionPhase.Authorizing
  assert services.workSubmissionInfo(token).extrinsicBytes == 6
  assert services.beginWorkSubmission(header, f.limits, executionLimits()).error ==
      StateProofAdmissionError.Busy
  services.waitDone()
  assert not services.stateProofAvailable
  assert services.collectWorkSubmission(default(WorkSessionToken)) == WorkSessionPhase.Empty
  assert services.stateProofActive
  assert services.collectWorkSubmission(token) == WorkSessionPhase.Authorized
  assert services.stateProofAvailable, "a network body wait must not reserve the CPU worker"
  assert not services.workSubmissionDuty(token).valid # Generic computation does not imply network guarantor eligibility.
  assert services.beginWorkSubmission(header, f.limits, executionLimits()).error ==
      StateProofAdmissionError.Busy
  let body = services.beginWorkBundle(token, f.extrinsics, f.segments, f.proofs)
  assert body.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.workSessionPhase(token) == WorkSessionPhase.Completing
  assert services.collectWorkSubmission(token) == WorkSessionPhase.Complete
  services.checkExecution(token)
  assert services.retireWorkSubmission(token)
  assert services.workSessionPhase(token) == WorkSessionPhase.Empty
  assert services.beginWorkBundle(token, f.extrinsics, f.segments, f.proofs).error ==
      StateProofAdmissionError.QueryFailure
  # Session generations reject stale controls even when the same complete source is reused.
  let next = services.beginWorkSubmission(header, f.limits, executionLimits()).value
  assert services.collectWorkSubmission(token) == WorkSessionPhase.Empty
  assert not services.retireWorkSubmission(token)
  services.waitDone()
  assert services.retireWorkSubmission(next)
  assert not services.reapWorkSubmission(), "cancelled Done still retains its exact CPU lease"
  assert services.collectWorkSubmission(next) == WorkSessionPhase.Retired
  assert services.reapWorkSubmission()
  # An unrelated exact CPU result remains untouched when an authorized body wait is abandoned.
  let waiting = services.beginWorkSubmission(header, f.limits, executionLimits()).value
  services.waitDone()
  assert services.collectWorkSubmission(waiting) == WorkSessionPhase.Authorized
  let foreign = services.beginNetworkRead(request)
  assert foreign.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.retireWorkSubmission(waiting)
  assert not services.reapWorkSubmission()
  assert services.collectWorkSubmission(waiting) == WorkSessionPhase.Retired
  assert services.stateProofPhase == ProofWorkerPhase.Done
  assert services.collectStateProof(foreign.value).kind == ProofWorkerCompletionKind.ReadCompleted
  assert services.reapWorkSubmission()
  # External stop plus a foreign replacement Done cannot be mistaken for the old work session.
  let stopped = services.beginWorkSubmission(header, f.limits, executionLimits()).value
  services.waitDone()
  services.stopStateProofs()
  let replacement = services.beginNetworkRead(request)
  assert replacement.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.retireWorkSubmission(stopped)
  assert services.collectWorkSubmission(stopped) == WorkSessionPhase.Retired
  assert services.stateProofPhase == ProofWorkerPhase.Done
  assert services.collectStateProof(replacement.value).kind ==
      ProofWorkerCompletionKind.ReadCompleted
  assert services.reapWorkSubmission()
  # A genuine body hash failure stays distinct from completed refinement and is safely retired.
  let failing = services.beginWorkSubmission(header, f.limits, executionLimits()).value
  services.waitDone()
  assert services.collectWorkSubmission(failing) == WorkSessionPhase.Authorized
  var changed = f.extrinsics
  changed[0] = changed[0] xor 1
  assert services.beginWorkBundle(failing, changed, f.segments, f.proofs).error ==
      StateProofAdmissionError.None
  services.waitDone()
  assert services.collectWorkSubmission(failing) == WorkSessionPhase.Failed
  block:
    # Genuine refusal extraction ends before the next worker starts.
    let outcome = services.workSubmissionOutcome(failing)
    assert outcome.kind == WorkJobResultKind.BodyFailure
    assert outcome.bodyError.error == WorkSubmissionError.ExtrinsicFailure
  assert services.retireWorkSubmission(failing)
  # CE133 consumes separately acquired authenticated import witnesses and reaches the same real refinement stage.
  var packageFirst = @[0'u8, 0]
  for octet in f.package: packageFirst.add(octet)
  let packageHeader = decodeWorkSubmission(WorkSubmissionKind.Package, packageFirst, [],
    fullPackageConfig(ByteLimit(204800))).value
  let packageToken = services.beginWorkSubmission(packageHeader, f.limits, executionLimits()).value
  services.waitDone()
  assert services.collectWorkSubmission(packageToken) == WorkSessionPhase.Authorized
  assert services.beginWorkPackage(packageToken, f.extrinsics, [@[inputProof(0)], @[inputProof(1)]],
    [inputPair(1)]).error == StateProofAdmissionError.None
  services.waitDone()
  assert services.collectWorkSubmission(packageToken) == WorkSessionPhase.Complete
  services.checkExecution(packageToken)
  assert services.retireWorkSubmission(packageToken)
  # Another Services namespace cannot collect, complete or retire this actor's session.
  var other = default(Services)
  defer: other.close()
  assert other.start(settings, "foreign managed work")
  let closing = services.beginWorkSubmission(header, f.limits, executionLimits()).value
  assert other.collectWorkSubmission(closing) == WorkSessionPhase.Empty
  assert not other.retireWorkSubmission(closing)
  assert other.beginWorkBundle(closing, f.extrinsics, f.segments, f.proofs).error ==
      StateProofAdmissionError.QueryFailure
  services.waitDone()
  services.close() # Joined close drops private source-bearing artifacts only after all borrowers retire.
  assert services.workSessionPhase(closing) == WorkSessionPhase.Empty
proc cycle(f: WorkFixture) =
  ## Private synchronous job execution releases original-source contexts and complete refinement on every success cycle.
  let admission = captureWorkAuthorization(f.workHeader, f.input.state, f.input.parameters,
      f.limits, executionLimits())
  assert admission.error == WorkJobError.None
  let authorized = executeWorkSubmission(admission.value)
  assert authorized.kind == WorkJobResultKind.Authorized
  let body = captureWorkBundle(authorized.context, f.extrinsics, f.segments, f.proofs)
  assert body.error == WorkJobError.None
  let completed = executeWorkSubmission(body.value)
  assert completed.kind == WorkJobResultKind.Refined
  assert completed.execution.inputRefinementSource.value.importInputsInfo.value.entries == 2
let fixture = workFixture()
try:
  # The actual full-state application path performs both CPU stages with opaque host controls.
  managed(fixture)
except:
  assert false, "managed work fixture setup"
cycle(fixture)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(fixture) # Repeated private source contexts and raw body copies must retire completely.
let after = getOccupiedMem()
assert before == after, "managed work ARC release"
recordArcRelease("jamnp_managed_work_submission", 1000, before, after)
echo "JAMNP-S managed work submission passed"
echo "ARC_RELEASE cycles=1000 unchanged"
