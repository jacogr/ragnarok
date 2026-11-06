# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Whole-message qualification and atomic private retention are exercised with real original signatures and independently computed complete state; a late failure never installs an accepted prefix.
import std/[assertions, monotimes, times, syncio, posix/posix]
import ../../src/app/[services, options, audit_state]
import ../../src/app/proof/worker
import ../../src/jamnp-s/[judgment_claim, judgment_support, judgment_receipt, audit_origin,
  audit_registry, audit_evaluation, audit_context, audits, work_signer]
import ../../src/jamnp-s/[audit_participation, audit_publication, availability_proof,
    availability_merkle, read_stream]
import ../../src/state/availability/specifier
import ../../src/jamnp-s/assurance_store
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, disputes, guarantees, report_owned]
import ../../src/codec/state/safrole
import ./[jamnp_audit_context, jamnp_audit_evaluation, jamnp_guarantee_support,
  jamnp_judgment_support, jamnp_audit_participation, current_application_context, assurance_signer_context]
proc processId(): cint {.importc: "getpid", header: "<unistd.h>".}
  ## Temporary checkpoint names are private to the native runner process.
proc receiptLimits*(): JudgmentReceiptLimits =
  ## Whole two-negative work reservations are separate from each per-record policy and full-map registry capacity.
  JudgmentReceiptLimits(support: actualSupportLimits(), origin: auditOriginLimits(),
    readBytes: ByteLimit(8000000), workspaceBytes: ByteLimit(128000000),
    hashBytes: ByteLimit(16000000), retainedBytes: ByteLimit(16000000),
    hashes: ElementLimit(8192), signatures: ElementLimit(6))
proc waitReceipt(owner: var Services) =
  ## Bound actual native worker completion independently of protocol timeout policy.
  let deadline = getMonoTime()+initDuration(seconds = 10)
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline
proc claimBatch(view: ChainView, records: openArray[AuditJudgment]): SignedJudgmentBatch =
  ## The real maintained Ed25519 verifier authenticates every original claim before support qualification starts.
  let wire = encodeJudgments(records, actualClaimLimits().message).value
  verifyJudgmentClaims(view, wire, actualClaimLimits()).value
proc stopReceipt(raw: nil pointer): bool {.nimcall, raises: [].} =
  ## Execution-only cancellation publishes neither a qualified record nor a private origin.
  true
proc judgmentReceiptChecks*(fixture: AuditContextFixture) {.raises.} =
  ## Duplicate sources retain their first exact owner; late invalid support, source, aggregate quota and native Done cancellation expose no successful prefix.
  let source = supportFixture(fixture)
  let first = unseenGuarantee(source)
  let second = unseenGuarantee(source, mutation = 2)
  let a = actualNegativeClaim(fixture, first)
  let b = actualNegativeClaim(fixture, second)
  let inputs = [JudgmentSourceInput(source: fixture.blockHash, report: first.report),
    JudgmentSourceInput(source: fixture.blockHash, report: second.report)]
  let claims = claimBatch(fixture.view, [a.judgmentRecord, b.judgmentRecord])
  let prepared = prepareJudgmentReceipt(fixture.view, claims, inputs, receiptLimits())
  assert prepared.error == JudgmentReceiptError.None
  let batch = prepared.value
  assert batch.len == 2 and batch.negativeCount == 2
  assert array[32, byte](batch.judgmentAt(0).value.judgmentRecord.report) == array[32, byte](
      a.judgmentRecord.report)
  let firstOrigin = batch.negativeOriginAt(0).value
  let secondOrigin = batch.negativeOriginAt(1).value
  var registry = default(AuditOriginRegistry)
  var policy = registryLimits()
  policy.blocks = ElementLimit(1)
  assert registry.configure(policy)
  defer: registry.clear()
  assert registry.retainDisputes([firstOrigin, default(AuditDisputeOrigin)]).error ==
      AuditRegistryError.InvalidSource
  assert registry.len == 0, "late source refusal cannot retain a prefix"
  assert registry.retainDisputes([firstOrigin, secondOrigin]).error ==
      AuditRegistryError.LimitExceeded
  assert registry.len == 0, "whole batch capacity precedes the first insertion"
  let duplicated = prepareJudgmentReceipt(fixture.view,
    claimBatch(fixture.view, [a.judgmentRecord, a.judgmentRecord]), [inputs[0], inputs[0]],
        receiptLimits()).value
  let ids = registry.retainDisputes([firstOrigin, duplicated.negativeOriginAt(0).value]).value
  assert ids.len == 2 and ids[0] == ids[1] and registry.len == 1
  assert registry.target(ids[0], 0).value.sameAuditOrigin(firstOrigin.reportAt(0).value)
  assert registry.origin(ids[0]).error == AuditRegistryError.InvalidSource, "a disputed report is never presented as an available block"
  assert registry.target(ids[0], 1).error == AuditRegistryError.InvalidIndex
  assert registry.evaluation(ids[0], 0).error == AuditRegistryError.NotEvaluated
  let repeated = registry.retainDisputes([duplicated.negativeOriginAt(0).value]).value
  assert repeated[0] == ids[0]
  let earlierSupport = qualifyJudgmentSupportAt(fixture.view,
    fixture.prior.bestBlock.value.blockHash,
    a, first.report, actualSupportLimits()).value
  let earlier = captureAuditDisputeOrigin(fixture.view, earlierSupport, auditOriginLimits()).value
  assert array[32, byte](earlier.disputeInfo.value.executionHash) != array[32, byte](
      firstOrigin.disputeInfo.value.executionHash)
  assert array[32, byte](earlier.disputeInfo.value.auditorHash) == array[32, byte](
      firstOrigin.disputeInfo.value.auditorHash)
  let historicalRetry = registry.retainDisputes([earlier]).value
  assert historicalRetry[0] == ids[0] and registry.len == 1, "a different genuine reporting/execution root cannot consume another row for the same report and original auditor cohort"
  assert registry.target(ids[0], 0).value.sameAuditOrigin(firstOrigin.reportAt(0).value)
  assert not registry.target(ids[0], 0).value.sameAuditOrigin(earlier.reportAt(0).value), "deduplication preserves the first actual physical execution owner"
  var bad = b.judgmentRecord
  var signature = array[64, byte](bad.credentials[bad.credentialCount-1].signature)
  signature[0] = signature[0] xor 1
  bad.credentials[bad.credentialCount-1].signature = GuaranteeSignature(signature)
  let badClaims = claimBatch(fixture.view, [a.judgmentRecord, bad])
  let rejected = prepareJudgmentReceipt(fixture.view, badClaims, inputs, receiptLimits())
  assert rejected.error == JudgmentReceiptError.SupportFailure, "negative inline support is outside the auditor signature domain and requires its own actual verification"
  var limited = receiptLimits()
  limited.signatures = ElementLimit(5)
  assert prepareJudgmentReceipt(fixture.view, claims, inputs, limited).error ==
      JudgmentReceiptError.LimitExceeded
  assert prepareJudgmentReceipt(fixture.view, claims, inputs, receiptLimits(),
    assuranceScanControl(stopReceipt, nil)).error == JudgmentReceiptError.Cancelled
  var stateFile = "judgment-state-" & $processId() & ".json"
  writeFile(stateFile, currentApplicationText(fixture.view.bestBlock.value))
  defer: discard posix.unlink(stateFile.toCString())
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", stateFile], options)
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(options, "whole negative judgment receipt")
  assert owner.beginJudgmentReceipt(claims, inputs, receiptLimits()).error ==
      StateProofAdmissionError.QueryFailure, "omission never activates private audit retention"
  assert owner.configureAudits(registryLimits())
  let cancelled = owner.beginJudgmentReceipt(claims, inputs, receiptLimits()).value
  owner.waitReceipt()
  assert owner.collectStateProof(cancelled).kind == ProofWorkerCompletionKind.Uninitialized
  assert owner.cancelStateProof(cancelled)
  assert owner.collectAudit(cancelled).kind == ManagedAuditKind.Cancelled
  let started = owner.beginJudgmentReceipt(claims, inputs, receiptLimits()).value
  owner.waitReceipt()
  assert owner.collectStateProof(started).kind == ProofWorkerCompletionKind.Uninitialized, "generic collection cannot expose complete historical state"
  let completed = owner.collectAudit(started)
  assert completed.kind == ManagedAuditKind.JudgmentsRetained and completed.retainedJudgmentCount == 2
  let selected = completed.retainedJudgmentAt(0)
  assert selected.originId.valid and selected.judgment.valid
  let actual = captureAuditContext(fixture.view, fixture.blockHash, auditLimits()).value
  let planning = owner.beginAuditParticipation(selected.originId, 0,
    actual.auditorAt(2).value.ed25519, participationLimits()).value
  owner.waitReceipt()
  assert owner.collectStateProof(planning).kind == ProofWorkerCompletionKind.Uninitialized
  let planned = owner.collectAudit(planning)
  assert planned.kind == ManagedAuditKind.ParticipationPlanned
  assert planned.participationPlan.participationInfo.value.localValidators == 1
  assert uint64(planned.participationPlan.localValidatorAt(0).value) == 2
  assert owner.beginAuditSigning(selected.originId, 0, StateValidatorIndex(1)).error ==
      StateProofAdmissionError.QueryFailure, "a qualified negative claim is still not a completed local evaluation"
  let evaluation = owner.beginAuditEvaluation(selected.originId, 0, [], evaluationLimits()).value
  owner.waitReceipt()
  let evaluated = owner.collectAudit(evaluation)
  assert evaluated.kind == ManagedAuditKind.EvaluationFailure and
      evaluated.evaluationError.needsRecovery
  let header = first.report.ownedReportInfo.value.header
  let specifier = AvailabilitySpecifier(packageHash: header.packageHash,
    bundleLength: header.bundleLength,
    erasureRoot: header.erasureRoot, erasureShards: header.erasureShards,
    segmentRoot: header.segmentRoot, segmentCount: header.segmentCount)
  var original = -1
  for index in 0..<fixture.bundles.len:
    # Real original computation provenance selects raw proof bytes; the worker still authenticates every expected descriptor field before private evaluation.
    if array[32, byte](fixture.bundles[index].reportHash) == array[32, byte](actual.auditReportHash(
        0).value): original = index
  assert original >= 0
  let proof = AvailabilityMerkleLimits(bytes: ByteLimit(1000000), hashes: ElementLimit(10000),
      hashBytes: ByteLimit(1000000))
  var packets: seq[VerifiedAvailabilityTransfer] = @[]
  for index in [8, 2, 4, 6]:
    let packet = fixture.bundles[original].auditShards[index]
    packets.add(verifyAvailabilityTransfer(specifier, packet.request, packet.bundleShard,
      packet.segmentShards, packet.justification, proof).value)
  let recovery = owner.beginAuditRecoveryEvaluation(selected.originId, 0, packets, recoveryLimits(),
      evaluationLimits()).value
  owner.waitReceipt()
  let recovered = owner.collectAudit(recovery)
  assert recovered.kind == ManagedAuditKind.Evaluated and not recovered.evaluationInfo.positive
  var keyFile = "judgment-publication-key-" & $processId() & ".pem"
  var certificateFile = "judgment-publication-cert-" & $processId() & ".pem"
  assuranceSignerFiles(keyFile, certificateFile, 12)
  defer:
    discard posix.unlink(keyFile.toCString())
    discard posix.unlink(certificateFile.toCString())
  assert owner.configureAuditSigner(certificateFile, keyFile, actual.auditorAt(
      1).value.ed25519).error == WorkSigningSetupError.None
  let publicationLimits = AuditPublicationLimits(wireBytes: ByteLimit(100000),
      workspaceBytes: ByteLimit(1000000))
  let cancelledPublication = owner.beginAuditPublication(selected.originId, 0, StateValidatorIndex(
      1), publicationLimits).value
  owner.waitReceipt()
  assert owner.cancelStateProof(cancelledPublication)
  assert owner.collectAudit(cancelledPublication).kind == ManagedAuditKind.Cancelled
  let publication = owner.beginAuditPublication(selected.originId, 0, StateValidatorIndex(1),
      publicationLimits).value
  owner.waitReceipt()
  assert owner.collectStateProof(publication).kind == ProofWorkerCompletionKind.Uninitialized
  let published = owner.collectAudit(publication)
  assert published.kind == ManagedAuditKind.PublicationPrepared and published.publicationId ==
      selected.originId and published.publicationOrdinal == 0
  assert published.preparedPublication.reportReply.request.kind == ReadKind.Report
  assert array[32, byte](published.preparedPublication.signedJudgment.judgmentRecord.report) ==
      array[32, byte](a.judgmentRecord.report)
  assert owner.collectAudit(started).kind == ManagedAuditKind.Uninitialized, "stale receipt tickets cannot collect another operation"
