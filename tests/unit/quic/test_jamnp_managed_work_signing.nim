# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_managed_work_signing_arc_release"}

## Actual Services keeps private TLS signing keys frozen through exact CPU collection/cancellation and joined close.
import std/[assertions, envvars, syncio, monotimes, times]
import ../../../src/app/[services, options]
import ../../../src/app/proof/[worker, network_read, work_submission as work_jobs]
import ../../../src/jamnp-s/[work_signer, work_eligibility, work_submission, work_duty, work_stream,
    connections, node, read_stream, availability_read, availability_merkle, availability_proof]
import ../../../src/codec/state/safrole
import ../../../src/codec/bounded
import ../../../src/chain/[genesis, provider]
import ../../../src/state/computed/[guarantee, report]
import ../../../src/crypto/primitives
import ../../support/[jamnp_guarantee_fixture, jamnp_work_fixture, jamnp_work_report_fixture,
    pvm_input_refinement, arc_evidence, jamnp_node_probe, jamnp_topology_fixture]

import ../../support/jamnp_managed_work_context
import ../../support/jamnp_segment_batch_fixture
import ../../../src/state/availability/specifier

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
  assert services.configureWorkSigner(cert, key, fixture.local, guarantorStorageLimits()).error ==
      WorkSigningSetupError.Closed
  assert services.start(settings, "managed work signing")
  assert not services.workSigningConfigured
  let wrong = services.configureWorkSigner(cert, getEnv("RAGNAROK_TEST_KEY_B"), fixture.local,
      guarantorStorageLimits())
  assert wrong.error == WorkSigningSetupError.SignerFailure
  assert wrong.signerError.error == WorkSignerError.IdentityMismatch
  let wrongIdentity = services.configureWorkSigner(cert, key, default(StateEdKey),
      guarantorStorageLimits())
  assert wrongIdentity.error == WorkSigningSetupError.InvalidIdentity
  assert not services.workSigningConfigured
  assert services.configureWorkSigner(cert, key, fixture.local, guarantorStorageLimits()).error ==
      WorkSigningSetupError.None
  assert services.workSigningConfigured
  assert services.configureWorkSigner(cert, key, fixture.local, guarantorStorageLimits()).error ==
      WorkSigningSetupError.Busy
  let raw = workFixture()
  let headHash = services.chainView.bestBlock.value.blockHash
  assert services.publishFinalized(headHash) == ViewFinalizeError.None
  let header = services.networkHeader(fixture, raw, cert, key)
  let token = services.reportSession(fixture, raw, header)
  let foreign = services.beginWorkContribution(default(WorkSessionToken), fixture.local,
    StateTime(20), guaranteeLimits(), guarantorLimits())
  assert foreign.error == StateProofAdmissionError.QueryFailure
  let mismatch = services.beginWorkContribution(token, default(StateEdKey), StateTime(20),
      guaranteeLimits(), guarantorLimits())
  assert mismatch.error == StateProofAdmissionError.QueryFailure
  let eligibility = guaranteeLimits()
  let signing = services.beginWorkContribution(token, fixture.local, StateTime(20), eligibility,
      guarantorLimits())
  assert signing.error == StateProofAdmissionError.None
  assert services.workSessionPhase(token) == WorkSessionPhase.Signing
  assert services.workSigningConfigured # Scalar only; no key/source owner is touched by this observation.
  let busy = services.configureWorkSigner("missing-certificate", "missing-key", fixture.local,
      guarantorStorageLimits())
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
      guaranteeLimits(), guarantorLimits())
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
      guaranteeLimits(), guarantorLimits())
  assert closeAdmission.error == StateProofAdmissionError.None
  services.close()
  assert not services.workSigningConfigured
  assert services.workSessionPhase(closing) == WorkSessionPhase.Empty
proc capacity(fixture: GuaranteeFixture, cert, key: string) {.raises.} =
  ## Real signing refuses inadequate capture and a full retained store before disclosing another signature; old roots survive primary release.
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "managed-signing-chain.json"], settings)
  var services = default(Services)
  defer: services.close()
  assert services.start(settings, "retained guarantor capacity")
  var storage = guarantorStorageLimits()
  storage.entries = ElementLimit(1)
  let configured = services.configureWorkSigner(cert, key, fixture.local, storage)
  assert configured.error == WorkSigningSetupError.None
  let readPolicy = guarantorReadLimits()
  assert services.configureAvailabilityReads(readPolicy)
  let raw = workFixture()
  let finalized = services.chainView.bestBlock.value.blockHash
  assert services.publishFinalized(finalized) == ViewFinalizeError.None
  let header = services.networkHeader(fixture, raw, cert, key)
  let inadequate = services.reportSession(fixture, raw, header)
  var tiny = guarantorLimits()
  tiny.bytes = ByteLimit(1)
  let attempted = services.beginWorkContribution(inadequate, fixture.local, StateTime(20),
    guaranteeLimits(), tiny)
  assert attempted.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.retainedWorkBundles == 0 and services.retainedWorkBytes == 0
  assert services.collectWorkSubmission(inadequate) == WorkSessionPhase.Failed
  block:
    # Only a genuine failed retention child exists; no successful contribution can be extracted from this outcome.
    let failure = services.workSubmissionOutcome(inadequate)
    assert failure.kind == WorkJobResultKind.SigningFailure
    assert failure.signingError.error == WorkSignerError.RetentionFailure
    assert failure.signingError.retentionError.error == AvailabilityTransferError.LimitExceeded
  assert services.retireWorkSubmission(inadequate)
  let first = services.reportSession(fixture, raw, header)
  let admitted = services.beginWorkContribution(first, fixture.local, StateTime(20),
    guaranteeLimits(), guarantorLimits())
  assert admitted.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.retainedWorkBundles == 0 # Done bytes remain exclusively in the uncollected worker result.
  assert services.collectWorkSubmission(first) == WorkSessionPhase.Contributed
  let metadata = services.workSubmissionReportInfo(first)
  assert services.retainedWorkBundles == 1 and services.retainedWorkBytes > 0
  let bytes = services.retainedWorkBytes
  assert services.retireWorkSubmission(first)
  assert services.workSessionPhase(first) == WorkSessionPhase.Empty
  let next = services.reportSession(fixture, raw, header)
  let full = services.beginWorkContribution(next, fixture.local, StateTime(20),
    guaranteeLimits(), guarantorLimits())
  assert full.error == StateProofAdmissionError.QueryFailure
  assert full.captureError == WorkJobError.LimitExceeded
  assert services.stateProofAvailable and services.workSessionPhase(next) ==
      WorkSessionPhase.ReportReady
  for kind in [ReadKind.Bundle, ReadKind.Availability]:
    # The old source is served by a fresh managed read after its entire signed session retired and later work reached ReportReady.
    var payload: seq[byte] = @[]
    for octet in metadata.header.erasureRoot.bytes: payload.add(octet)
    if kind == ReadKind.Availability:
      payload.add(0)
      payload.add(0)
    let request = decodeReadRequest(kind, payload).value
    let reading = services.beginNetworkRead(request)
    assert reading.error == StateProofAdmissionError.None
    services.waitDone()
    assert services.retainedWorkBundles == 1 and services.retainedWorkBytes == bytes
    let blocked = services.beginWorkContribution(next, fixture.local, StateTime(20),
      guaranteeLimits(), guarantorLimits())
    assert blocked.error == StateProofAdmissionError.Busy
    block:
      # Matching read collection exposes independent wire; ARC aliases retire before the next signing/read admission.
      let completed = services.collectStateProof(reading.value)
      assert completed.kind == ProofWorkerCompletionKind.ReadCompleted
      let reply = completed.readValue
      assert reply.error == ReadError.None
      if kind == ReadKind.Bundle:
        var expected: seq[byte] = @[]
        for octet in fixture.package: expected.add(octet)
        for octet in raw.extrinsics: expected.add(octet)
        for octet in raw.segments: expected.add(octet)
        for octet in raw.proofs: expected.add(octet)
        assert reply.value.bytes == frame(expected)
  assert services.retireWorkSubmission(next)
  assert services.retainedWorkBundles == 1 and services.retainedWorkBytes == bytes
proc retainedRoot(services: var Services, fixture: GuaranteeFixture, raw: WorkFixture,
    cert, key: string): array[32, byte] {.raises.} =
  ## Independent genuine builder headers produce signatures and then retire every session-owned source before returning only fixed root bytes.
  let header = services.networkHeader(fixture, raw, cert, key)
  let token = services.reportSession(fixture, raw, header)
  let signing = services.beginWorkContribution(token, fixture.local, StateTime(20),
    guaranteeLimits(), guarantorLimits())
  assert signing.error == StateProofAdmissionError.None
  services.waitDone()
  assert services.collectWorkSubmission(token) == WorkSessionPhase.Contributed
  result = services.workSubmissionReportInfo(token).header.erasureRoot.bytes
  assert services.retireWorkSubmission(token)
  assert services.workSessionPhase(token) == WorkSessionPhase.Empty
proc multiple(fixture: GuaranteeFixture, cert, key: string) {.raises.} =
  ## Two actual packages share one canonical source but distinct authorization bytes; later signatures cannot replace earlier serving roots.
  let changed = guaranteeFixture(fixture.local, authorizationSalt = 1)
  let oldParent = fixture.view.parentOf(fixture.view.bestBlock.value.blockHash).value
  let newParent = changed.view.parentOf(changed.view.bestBlock.value.blockHash).value
  assert array[32, byte](oldParent.stateRoot) == array[32, byte](newParent.stateRoot)
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "managed-signing-chain.json"], settings)
  var services = default(Services)
  defer: services.close()
  assert services.start(settings, "multiple retained guarantor roots")
  var storage = guarantorStorageLimits()
  storage.entries = ElementLimit(2)
  let configured = services.configureWorkSigner(cert, key, fixture.local, storage)
  assert configured.error == WorkSigningSetupError.None
  let policy = guarantorReadLimits()
  assert services.configureAvailabilityReads(policy)
  let finalized = services.chainView.bestBlock.value.blockHash
  assert services.publishFinalized(finalized) == ViewFinalizeError.None
  let raw = workFixture()
  let roots = [services.retainedRoot(fixture, raw, cert, key), services.retainedRoot(changed, raw,
      cert, key)]
  assert roots[0] != roots[1] and services.retainedWorkBundles == 2
  for ordinal in 0..<2:
    # Check every six-validator shard plus the full original bundle through fresh managed jobs after both sessions retired.
    let original = if ordinal == 0: fixture.transcript else: changed.transcript
    let source = original.computedGuaranteeReport.value.computedReportSource.value
    for coordinate in 0..6:
      let kind = if coordinate == 6: ReadKind.Bundle else: ReadKind.Availability
      var payload: seq[byte] = @[]
      for octet in roots[ordinal]: payload.add(octet)
      if kind == ReadKind.Availability:
        payload.add(byte(coordinate))
        payload.add(0)
      let request = decodeReadRequest(kind, payload).value
      let expected = serveAvailabilityRead(source, request, policy)
      assert expected.error == ReadError.None
      let admitted = services.beginNetworkRead(request)
      assert admitted.error == StateProofAdmissionError.None
      services.waitDone()
      block:
        # Exact collection retires the raw reply before any next worker can borrow cache aliases.
        let completed = services.collectStateProof(admitted.value)
        assert completed.kind == ProofWorkerCompletionKind.ReadCompleted
        assert completed.readValue.error == ReadError.None
        assert completed.readValue.value.bytes == expected.value.bytes
  assert services.retainedWorkBundles == 2
proc segments(local: StateEdKey, cert, key: string) {.raises.} =
  ## A real exporting signature remains queryable after retirement while a distinct unsigned report supplies another root in the same batch.
  let fixture = guaranteeFixture(local, exported = true)
  let next = guaranteeFixture(local, exported = true, declaredExports = 2)
  let parent = fixture.view.parentOf(fixture.view.bestBlock.value.blockHash).value
  let nextParent = next.view.parentOf(next.view.bestBlock.value.blockHash).value
  assert array[32, byte](parent.stateRoot) == array[32, byte](nextParent.stateRoot)
  writeFile("managed-segments-chain.json", workChainText(parent))
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain",
      "managed-segments-chain.json"], settings)
  var services = default(Services)
  defer: services.close()
  assert services.start(settings, "retained original segment batches")
  let configured = services.configureWorkSigner(cert, key, local, guarantorStorageLimits())
  assert configured.error == WorkSigningSetupError.None
  var policy = guarantorReadLimits()
  policy.computation.hashes = ElementLimit(1) # Only the retained one-export tree needs a fresh hash; the live original tree already exists.
  policy.computation.hashBytes = ByteLimit(4108)
  assert services.configureAvailabilityReads(policy)
  assert services.publishFinalized(services.chainView.bestBlock.value.blockHash) ==
      ViewFinalizeError.None
  let raw = workFixture(exported = true)
  discard services.retainedRoot(fixture, raw, cert, key)
  let previous = fixture.transcript.computedGuaranteeReport.value.computedReportSource.value
  let incoming = next.transcript.computedGuaranteeReport.value.computedReportSource.value
  let a = previous.availabilityInfo.value.specifier
  let b = incoming.availabilityInfo.value.specifier
  assert uint16(a.segmentCount) == 1 and uint16(b.segmentCount) == 2
  assert a.segmentRoot.bytes != b.segmentRoot.bytes
  let header = services.networkHeader(next, raw, cert, key)
  let token = services.reportSession(next, raw, header)
  assert services.workSessionPhase(token) == WorkSessionPhase.ReportReady
  assert services.retainedWorkBundles == 1
  var payload = segmentGroup(ReadKind.Segments, a.segmentRoot.bytes, 0, [0'u16])
  for octet in segmentGroup(ReadKind.Segments, b.segmentRoot.bytes, 0, [1'u16]): payload.add(octet)
  for octet in segmentGroup(ReadKind.Segments, a.segmentRoot.bytes, 0, [0'u16]): payload.add(octet)
  let request = decodeReadRequest(ReadKind.Segments, payload).value
  let reading = services.beginNetworkRead(request)
  assert reading.error == StateProofAdmissionError.None
  services.waitDone()
  assert not services.stateProofAvailable and services.retainedWorkBundles == 1
  assert services.retireWorkSubmission(token) # Retiring the live primary cannot release any alias held by this foreign Done read.
  assert services.workSessionPhase(token) == WorkSessionPhase.Retired
  block:
    # Only exact read collection releases both live-original and retained-source aliases; independent original computation checks every ordered fragment.
    let completed = services.collectStateProof(reading.value)
    assert completed.kind == ProofWorkerCompletionKind.ReadCompleted
    assert completed.readValue.error == ReadError.None
    var data, proofs: seq[byte] = @[]
    for ordinal in 0..<3:
      let original = if ordinal == 1: incoming else: previous
      let info = if ordinal == 1: b else: a
      let row = if ordinal == 1: 1'u16 else: 0'u16
      let single = decodeReadRequest(ReadKind.Segments, segmentGroup(ReadKind.Segments,
          info.segmentRoot.bytes, 0, [row])).value
      let parts = segmentMessages(serveOriginalSegmentBatch(original, single, guarantorReadLimits()).value.bytes)
      verifyOriginalSegments(info, [row], parts)
      for octet in parts[0]: data.add(octet)
      for octet in parts[1]: proofs.add(octet)
    assert segmentMessages(completed.readValue.value.bytes) == @[data, proofs]
  assert services.reapWorkSubmission()
  assert services.retainedWorkBundles == 1
proc cycle(worker: var StateProofWorker, context: AuthorizedWorkContext, fixture: GuaranteeFixture,
    signer: WorkSigner, mode: int) =
  ## Shared worker ownership covers real success, Done cancellation and a late mismatched-private-key refusal.
  let expected = fixture.local
  var captured = captureWorkContribution(context, fixture.transcript, fixture.view, expected,
    StateTime(21), signer, guaranteeLimits(), guarantorLimits()).value
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
proc readSource(local: StateEdKey, signer: WorkSigner): GuarantorAvailability =
  ## Every temporary qualification/signature alias retires before the source-free archive is handed to the worker stress loop.
  let fixture = guaranteeFixture(local, exported = true)
  let qualified = fixture.qualify(guaranteeLimits())
  assert qualified.error == WorkEligibilityError.None
  let contributed = signer.signWorkContribution(qualified.value, guarantorLimits())
  assert contributed.error == WorkSignerError.None
  contributed.value.contributionAvailability.value
proc readJob(source: GuarantorAvailability, request: ReadRequest): NetworkReadJob =
  ## Array/admission temporaries leave this staging activation before submit transfers the only job owner to the worker.
  let captured = captureOriginalSegments(default(AvailabilityCommitment), [source], request,
      guarantorReadLimits())
  assert captured.error == ReadError.None
  captured.value
proc readCycle(worker: var StateProofWorker, source: GuarantorAvailability, cancel: bool) =
  ## Actual immutable archive/table/tree lifetimes survive handoff, foreign collection and Done cancellation without leaking across cycles.
  let info = source.guarantorInfo.value.specifier
  let request = decodeReadRequest(ReadKind.Segments, segmentGroup(ReadKind.Segments,
      info.segmentRoot.bytes, 0, [0'u16, 0])).value
  var job = readJob(source, request)
  let admitted = worker.submit(job)
  assert admitted.error == ProofWorkerError.None and not job.valid
  worker.waitDone()
  assert worker.collect(default(ProofWorkerTicket)).kind == ProofWorkerCompletionKind.Uninitialized
  if cancel: assert worker.cancel(admitted.value)
  let completed = worker.collect(admitted.value)
  if cancel:
    assert completed.kind == ProofWorkerCompletionKind.Cancelled
  else:
    assert completed.kind == ProofWorkerCompletionKind.ReadCompleted
    assert completed.readValue.error == ReadError.None
    verifyOriginalSegments(info, [0'u16, 0], segmentMessages(completed.readValue.value.bytes))
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
  capacity(fixture, cert, key)
  multiple(fixture, cert, key)
  segments(fixture.local, cert, key)
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
  let archive = readSource(fixture.local, signer.value)
  readCycle(worker, archive, false)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # All source/key aliases remain untouched between submit and matching collection inside each cycle.
    let mode = iteration mod 3
    if mode == 2: cycle(worker, authorized.context, fixture, other.value, mode)
    else: cycle(worker, authorized.context, fixture, signer.value, mode)
    readCycle(worker, archive, iteration mod 2 == 1)
  let after = getOccupiedMem()
  assert before == after, "managed signing releases private key/job/report aliases on every terminal path"
  recordArcRelease("jamnp_managed_work_signing", 1000, before, after)
  echo "JAMNP-S managed work signing passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main()
except:
  quit 2 # Startup/setup exceptions must never stand in for contribution or lifetime evidence.
