# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_managed_work_signing_arc_release"}

## Actual Services keeps private TLS signing keys frozen through exact CPU collection/cancellation and joined close.
import std/[assertions, envvars, syncio, monotimes, times]
import ../../../src/app/[services, options]
import ../../../src/app/proof/[worker, work_submission as work_jobs]
import ../../../src/jamnp-s/[work_signer, work_eligibility, work_submission, work_duty, work_stream,
    connections, node, read_stream, availability_read, availability_merkle]
import ../../../src/codec/state/safrole
import ../../../src/codec/bounded
import ../../../src/chain/[genesis, provider]
import ../../../src/state/computed/guarantee
import ../../../src/crypto/primitives
import ../../support/[jamnp_guarantee_fixture, jamnp_work_fixture, jamnp_work_report_fixture,
    pvm_input_refinement, arc_evidence, jamnp_node_probe, jamnp_topology_fixture]

import ../../support/jamnp_managed_work_context

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield between scalar polls without reading any signer/source owner held by the CPU.
proc waitDone(worker: var StateProofWorker) =
  ## All source/key aliases remain frozen while polling only the synchronized phase.
  let deadline = getMonoTime()+initDuration(seconds = 20)
  while worker.phase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "signing worker deadline"
    discard pauseMicros(1000)
proc verifyContribution(contribution: SignedWorkContribution, expected: StateEdKey, slot: uint32) =
  ## Genuine collected signatures authenticate the exact retained transcript and actual original roster ordinal.
  let facts = contribution.contributionInfo.value
  let credential = contribution.contributionCredential.value
  assert uint16(credential.validator) == 1 and uint32(facts.slot) == slot
  assert array[32, byte](facts.identity) == array[32, byte](expected)
  let message = array[45, byte](contribution.contributionTranscript.value.computedGuaranteeMessage.value)
  assert verify(EdPublicKey(array[32, byte](expected)), EdSignature(array[64, byte](
      credential.signature)), message)
proc collected(services: Services, token: WorkSessionToken, expected: StateEdKey) =
  ## Every extracted ARC alias retires before this helper returns and another worker may be admitted.
  let outcome = services.workSubmissionOutcome(token)
  assert outcome.kind == WorkJobResultKind.Contributed
  verifyContribution(outcome.signedContribution, expected, 20)
proc managed(fixture: GuaranteeFixture, cert, key: string) {.raises.} =
  ## Configuration imports from paths privately and only while the full-state worker/session is idle.
  let head = fixture.view.bestBlock.value
  let parent = fixture.view.parentOf(head.blockHash)
  assert parent.error == GenesisError.None
  writeFile("managed-signing-chain.json", workChainText(parent.value))
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "managed-signing-chain.json"], settings)
  var services = default(Services)
  defer: services.close()
  assert services.configureWorkSigner(cert, key, fixture.local).error ==
      WorkSigningSetupError.Closed
  assert services.start(settings, "managed work signing")
  assert not services.workSigningConfigured
  let wrong = services.configureWorkSigner(cert, getEnv("RAGNAROK_TEST_KEY_B"), fixture.local)
  assert wrong.error == WorkSigningSetupError.SignerFailure
  assert wrong.signerError.error == WorkSignerError.IdentityMismatch
  let wrongIdentity = services.configureWorkSigner(cert, key, default(StateEdKey))
  assert wrongIdentity.error == WorkSigningSetupError.InvalidIdentity
  assert not services.workSigningConfigured
  assert services.configureWorkSigner(cert, key, fixture.local).error == WorkSigningSetupError.None
  assert services.workSigningConfigured
  assert services.configureWorkSigner(cert, key, fixture.local).error == WorkSigningSetupError.Busy
  let raw = workFixture()
  let headHash = services.chainView.bestBlock.value.blockHash
  assert services.publishFinalized(headHash) == ViewFinalizeError.None
  let header = services.networkHeader(fixture, raw, cert, key)
  let token = services.reportSession(fixture, raw, header)
  let foreign = services.beginWorkContribution(default(WorkSessionToken), fixture.local,
    StateTime(20), guaranteeLimits())
  assert foreign.error == StateProofAdmissionError.QueryFailure
  let mismatch = services.beginWorkContribution(token, default(StateEdKey), StateTime(20),
      guaranteeLimits())
  assert mismatch.error == StateProofAdmissionError.QueryFailure
  let signing = services.beginWorkContribution(token, fixture.local, StateTime(20), guaranteeLimits())
  assert signing.error == StateProofAdmissionError.None
  assert services.workSessionPhase(token) == WorkSessionPhase.Signing
  assert services.workSigningConfigured # Scalar only; no key/source owner is touched by this observation.
  let busy = services.configureWorkSigner("missing-certificate", "missing-key", fixture.local)
  assert busy.error == WorkSigningSetupError.Busy
  services.waitDone()
  assert not services.stateProofAvailable and services.workSessionPhase(token) ==
      WorkSessionPhase.Signing
  assert services.collectWorkSubmission(default(WorkSessionToken)) == WorkSessionPhase.Empty
  assert services.stateProofActive
  assert services.collectWorkSubmission(token) == WorkSessionPhase.Contributed
  let facts = services.workSignedInfo(token)
  assert uint16(facts.validator) == 1 and uint32(facts.slot) == 20
  services.collected(token, fixture.local)
  let metadata = services.workSubmissionReportInfo(token)
  let readPolicy = AvailabilityReadLimits(computation: AvailabilityMerkleLimits(bytes: ByteLimit(
      64000000),
    hashBytes: ByteLimit(16000000), hashes: ElementLimit(10000)), wireBytes: ByteLimit(16000000))
  assert services.configureAvailabilityReads(readPolicy)
  let request = decodeReadRequest(ReadKind.Bundle, metadata.header.erasureRoot.bytes)
  assert request.error == ReadError.None
  let reading = services.beginNetworkRead(request.value)
  assert reading.error == StateProofAdmissionError.None, "signed contribution preserves bundle serving"
  services.waitDone()
  block:
    # The reply contains detached exact bytes; all response owners retire before session retirement.
    let completed = services.collectStateProof(reading.value)
    assert completed.kind == ProofWorkerCompletionKind.ReadCompleted
    let reply = completed.readValue
    assert reply.error == ReadError.None
    var expected: seq[byte] = @[]
    for octet in fixture.package: expected.add(octet)
    for octet in raw.extrinsics: expected.add(octet)
    for octet in raw.segments: expected.add(octet)
    for octet in raw.proofs: expected.add(octet)
    assert reply.value.bytes == frame(expected)
  assert services.retireWorkSubmission(token)
  assert services.workSessionPhase(token) == WorkSessionPhase.Empty
  # Cancelling an already Done signature cannot expose it or release the signer lease early.
  let cancelled = services.reportSession(fixture, raw, header)
  let cancelAdmission = services.beginWorkContribution(cancelled, fixture.local, StateTime(20),
      guaranteeLimits())
  assert cancelAdmission.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.retireWorkSubmission(cancelled)
  assert not services.stateProofAvailable
  assert services.collectWorkSubmission(cancelled) == WorkSessionPhase.Retired
  assert services.reapWorkSubmission()
  assert services.workSessionPhase(cancelled) == WorkSessionPhase.Empty
  # Joined close owns all pending aliases and wipes its private key only after the worker terminates.
  let closing = services.reportSession(fixture, raw, header)
  let closeAdmission = services.beginWorkContribution(closing, fixture.local, StateTime(20),
      guaranteeLimits())
  assert closeAdmission.error == StateProofAdmissionError.None
  services.close()
  assert not services.workSigningConfigured
  assert services.workSessionPhase(closing) == WorkSessionPhase.Empty
proc cycle(worker: var StateProofWorker, context: AuthorizedWorkContext, fixture: GuaranteeFixture,
    signer: WorkSigner, mode: int) =
  ## Shared worker ownership covers real success, Done cancellation and a late mismatched-private-key refusal.
  let expected = fixture.local
  var captured = captureWorkContribution(context, fixture.transcript, fixture.view, expected,
    StateTime(21), signer, guaranteeLimits()).value
  let admitted = worker.submit(captured)
  assert admitted.error == ProofWorkerError.None
  assert not captured.valid
  let ticket = admitted.value
  worker.waitDone()
  var empty = default(WorkSubmissionJob)
  assert worker.submit(empty).error == ProofWorkerError.Busy
  assert worker.collect(default(ProofWorkerTicket)).kind == ProofWorkerCompletionKind.Uninitialized
  assert worker.phase == ProofWorkerPhase.Done
  if mode == 1:
    # Cancellation discards a genuine completed signature while retaining capacity until exact collection.
    assert worker.cancel(ticket)
  let completion = worker.collect(ticket)
  if mode == 1:
    assert completion.kind == ProofWorkerCompletionKind.Cancelled
  else:
    # Successful collection alone can expose either the genuine signature or a precise late signer failure.
    assert completion.kind == ProofWorkerCompletionKind.WorkSubmitted
    let outcome = completion.workSubmissionValue
    if mode == 2:
      assert outcome.kind == WorkJobResultKind.SigningFailure
      assert outcome.signingError.error == WorkSignerError.IdentityMismatch
    else:
      verifyContribution(outcome.signedContribution, expected, 21)
  assert worker.phase == ProofWorkerPhase.Idle
proc main() {.raises.} =
  ## Test-only TLS fixtures are read privately; no key material is printed or installed by mutable alias.
  let cert = getEnv("RAGNAROK_TEST_CERT")
  let key = getEnv("RAGNAROK_TEST_KEY")
  let signer = loadWorkSigner(cert, key)
  assert signer.error == WorkSignerError.None
  let other = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"))
  assert other.error == WorkSignerError.None
  let fixture = guaranteeFixture(signer.value.signerIdentity.value)
  managed(fixture, cert, key)
  let raw = workFixture()
  let admitted = captureWorkAuthorization(fixture.original, fixture.execution,
    fixture.view.bestBlock.value.chainParameters, raw.limits, executionLimits())
  assert admitted.error == WorkJobError.None
  let authorized = executeWorkSubmission(admitted.value)
  assert authorized.kind == WorkJobResultKind.Authorized
  var worker = default(StateProofWorker)
  defer: worker.close()
  assert worker.start()
  cycle(worker, authorized.context, fixture, signer.value, 0)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # All source/key aliases remain untouched between submit and matching collection inside each cycle.
    let mode = iteration mod 3
    if mode == 2: cycle(worker, authorized.context, fixture, other.value, mode)
    else: cycle(worker, authorized.context, fixture, signer.value, mode)
  let after = getOccupiedMem()
  assert before == after, "managed signing releases private key/job/report aliases on every terminal path"
  recordArcRelease("jamnp_managed_work_signing", 1000, before, after)
  echo "JAMNP-S managed work signing passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main()
except:
  quit 2 # Startup/setup exceptions must never stand in for contribution or lifetime evidence.
