# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Whole-message qualification and atomic private retention are exercised with real original signatures and independently computed complete state; a late failure never installs an accepted prefix.
import std/[assertions, monotimes, times, syncio, posix/posix]
import ../../src/app/[services, options, audit_state]
import ../../src/app/proof/worker
import ../../src/jamnp-s/[judgment_claim, judgment_support, judgment_receipt, audit_origin,
  audit_registry, audit_evaluation, audit_context, audits, work_signer, judgment_store, judgment_source]
import ../../src/jamnp-s/[audit_participation, audit_publication, availability_proof,
    availability_merkle, read_stream]
import ../../src/state/availability/specifier
import ../../src/jamnp-s/assurance_store
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, disputes, guarantees, report_owned]
import ../../src/codec/state/safrole
import ../../src/codec/[header, owned]
import ../../src/codec/state/layout
import ../../src/state/store
import ./[jamnp_audit_context, jamnp_audit_evaluation, jamnp_guarantee_support,
  jamnp_judgment_support, jamnp_audit_participation, current_application_context, assurance_signer_context]
import ./jamnp_judgment_claim
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
proc fullEpochLedgerChecks(view: ChainView) =
  ## A single genuine judgment per slot in the full profile exceeds the former local ceiling.
  var ledger = default(JudgmentStore)
  assert ledger.configure(JudgmentStoreLimits(records: ElementLimit(600), bytes: ByteLimit(1000000)))
  for group in 0..<38:
    let offset = group*16
    var records: seq[AuditJudgment] = @[]
    var inputs: seq[JudgmentSourceInput] = @[]
    for index in offset..<min(offset+16, 600):
      let ordinal = index div 256
      records.add(rawClaim(1, uint16(ordinal), byte(21+ordinal), hashMarker = byte(index mod 256)))
      inputs.add(default(JudgmentSourceInput))
    let claims = verifyJudgmentClaims(view, claimWire(records), claimLimits()).value
    let batch = prepareJudgmentReceipt(view, claims, inputs, receiptLimits()).value
    var qualified: seq[QualifiedJudgment] = @[]
    for index in 0..<batch.len: qualified.add(batch.judgmentAt(index).value)
    assert ledger.append(qualified).value == records.len
  assert ledger.len == 600
  ledger.expireBefore(2)
  assert ledger.len == 0
proc sameKeyBranchSupport(fixture: AuditContextFixture, claim: SignedJudgmentClaim,
    report: OwnedReport) =
  ## Selected membership has the correct signing key but lacks the guaranteed reporting context.
  let tip = fixture.view.bestBlock.value
  var state = forkStateStore(tip.stateSnapshot).value
  let entropyKey = chapterKey(StateChapter(6))
  let removed = state.apply([StateWrite(kind: StateWriteKind.Delete, key: entropyKey)])
  assert removed.error == StateStoreError.None
  var headerWire = newSeq[byte](tip.header.headerInfo.value.consumed)
  assert tip.header.encodeOwnedHeader(headerWire).error == HeaderError.None
  headerWire[64] = headerWire[64] xor 1
  let selected = genesisView(captureBlockSnapshot(headerWire, state.snapshot.value,
      tip.chainParameters))
  let primary = claimBatch(selected, [claim.judgmentRecord])
  let signed = primary.claimAt(0).value
  let original = selectJudgmentSource(selected, signed).value
  let refused = prepareJudgmentReceipt(selected, primary,
      [JudgmentSourceInput(source: original, report: report)], receiptLimits())
  assert refused.error == JudgmentReceiptError.SupportFailure
  let alternative = alternateJudgmentSource(fixture.view, signed, [JudgmentSourceAttempt(
      source: original)])
  assert alternative.error == JudgmentSourceError.None
  let input = JudgmentSourceInput(source: fixture.prior.bestBlock.value.blockHash,
      membership: alternative.membershipSource, report: report)
  let checked = prepareJudgmentReceipt(selected, primary, [input], receiptLimits(),
      alternatives = [fixture.view])
  assert checked.error == JudgmentReceiptError.None, "a valid side reporting context can certify the same signed claim"
  let origin = checked.value.negativeOriginAt(0).value
  assert origin.matchesTrustedDispute(fixture.view) and not origin.matchesTrustedDispute(selected)
  let earlier = claimBatch(fixture.view, [claim.judgmentRecord]).claimAt(0).value
  let newest = selectJudgmentSourceAcross(fixture.view, [selected], earlier, [], high(uint64)).value
  let firstFailure = JudgmentSourceAttempt(source: newest)
  let alternate = selectJudgmentSourceAcross(fixture.view, [selected], earlier, [firstFailure],
      high(uint64))
  assert alternate.error == JudgmentSourceError.None and
      array[32, byte](alternate.membershipSource) == array[32, byte](
          selected.bestBlock.value.blockHash)
  let secondFailure = JudgmentSourceAttempt(source: alternate.value,
      membership: alternate.membershipSource)
  let fallback = selectJudgmentSourceAcross(fixture.view, [selected], earlier,
      [firstFailure, secondFailure], high(uint64))
  assert fallback.error == JudgmentSourceError.None
  assert array[32, byte](fallback.value) == array[32, byte](
      fixture.prior.bestBlock.value.blockHash),
      "the alternate cannot consume the retry reserved for another live history"

proc retryOriginLimit(fixture: AuditContextFixture, claim: SignedJudgmentClaim,
    report: OwnedReport) =
  ## The same original guarantee can verify in both contexts while only one map fits.
  let prior = fixture.prior.bestBlock.value
  var state = forkStateStore(prior.stateSnapshot).value
  let extraKey = chapterKey(StateChapter(254))
  let expanded = state.apply([StateWrite(kind: StateWriteKind.Put, key: extraKey, value: @[1'u8])])
  assert expanded.error == StateStoreError.None
  var headerWire = newSeq[byte](prior.header.headerInfo.value.consumed)
  assert prior.header.encodeOwnedHeader(headerWire).error == HeaderError.None
  headerWire[64] = headerWire[64] xor 1
  let checkpoint = captureBlockSnapshot(headerWire, state.snapshot.value, prior.chainParameters)
  let primary = genesisView(checkpoint)
  let claims = claimBatch(primary, [claim.judgmentRecord])
  var limits = receiptLimits()
  limits.origin.entries = ElementLimit(uint64(prior.stateSnapshot.commitment.entries))
  let input = JudgmentSourceInput(source: checkpoint.value.blockHash, report: report)
  let failed = prepareJudgmentReceipt(primary, claims, [input], limits)
  assert failed.error == JudgmentReceiptError.OriginFailure
  assert failed.originError.error == AuditOriginError.LimitExceeded and failed.failedOrdinal == 0
  let alternative = JudgmentSourceInput(source: prior.blockHash,
      membership: fixture.view.bestBlock.value.blockHash, report: report)
  assert prepareJudgmentReceipt(primary, claims, [alternative], limits,
      alternatives = [fixture.view]).error == JudgmentReceiptError.None
proc judgmentReceiptChecks*(fixture: AuditContextFixture) {.raises.} =
  ## Duplicate sources retain their first exact owner; late invalid support, source, aggregate quota and native Done cancellation expose no successful prefix.
  let selectedRoster = claimView(repeated = true)
  let side = claimView()
  fullEpochLedgerChecks(side)
  let wire = claimWire([rawClaim(1, 1, 21), rawClaim(1, 1, 22)])
  let mixed = verifyJudgmentClaims(selectedRoster, wire, claimLimits(), alternatives = [side]).value
  let empty = default(JudgmentSourceInput)
  assert prepareJudgmentReceipt(selectedRoster, mixed, [empty, empty], receiptLimits()).error ==
      JudgmentReceiptError.InvalidSource
  let receipt = prepareJudgmentReceipt(selectedRoster, mixed, [empty, empty], receiptLimits(),
      alternatives = [side]).value
  var ledger = default(JudgmentStore)
  assert ledger.configure(JudgmentStoreLimits(records: ElementLimit(2), bytes: ByteLimit(16000)))
  assert ledger.canAppendClaims(mixed)
  assert ledger.append([receipt.judgmentAt(0).value, receipt.judgmentAt(1).value]).value == 2,
      "different authenticated keys at the same ordinal must not collapse across rosters"
  let source = supportFixture(fixture)
  let first = unseenGuarantee(source)
  let second = unseenGuarantee(source, mutation = 2)
  let a = actualNegativeClaim(fixture, first)
  sameKeyBranchSupport(fixture, a, first.report)
  retryOriginLimit(fixture, a, first.report)
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
  assert registry.releaseDispute(ids[0]) and registry.len == 0
  assert registry.target(ids[0], 0).error == AuditRegistryError.InvalidId
  let restored = registry.retainDisputes([firstOrigin]).value[0]
  assert restored != ids[0] and registry.len == 1, "release recovers bounded capacity without recycling IDs"
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
