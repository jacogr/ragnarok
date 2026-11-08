# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## An originally unseen signed report uses actual standalone support and complete historical execution state; only root-authenticated recovery can justify its negative local judgment.

import std/[assertions, syncio, posix/posix]
import ../../src/jamnp-s/[audit_origin, audit_context, audit_evaluation, audit_recovery,
  judgment_support, work_signer, availability_proof, availability_merkle, audit_fetch]
import ../../src/jamnp-s/[audit_publication, judgment_receipt, read_stream]
import ../../src/jamnp-s/assurance_store
import ../../src/state/availability/specifier
import ../../src/codec/[bounded, report_owned, disputes]
import ../../src/codec/state/safrole
import ../../src/chain/[genesis, provider, reports]
import ../../src/crypto/primitives
import ./[jamnp_audit_context, jamnp_audit_evaluation, jamnp_guarantee_support,
  jamnp_judgment_support, assurance_signer_context]

proc processId(): cint {.importc: "getpid", header: "<unistd.h>".}
  ## Native runner artifacts are process-private and explicitly removed after key owners retire.

proc stopDispute(raw: nil pointer): bool {.nimcall, raises: [].} =
  ## A trusted cancellation callback cannot fabricate execution evidence.
  true

proc disputeEvaluationChecks*(fixture: AuditContextFixture) {.raises.} =
  ## Original unknown report bytes are genuinely signed before qualification; an absent availability block stays absent through actual recovery, evaluation and signing.
  let guarantee = unseenGuarantee(supportFixture(fixture))
  let claim = actualNegativeClaim(fixture, guarantee)
  let support = qualifyJudgmentSupportAt(fixture.view, fixture.prior.bestBlock.value.blockHash,
    claim, guarantee.report, actualSupportLimits()).value
  let captured = captureAuditDisputeOrigin(fixture.view, support, auditOriginLimits())
  assert captured.error == AuditOriginError.None
  let origin = captured.value
  assert origin.matchesTrustedDispute(fixture.view)
  assert not origin.matchesTrustedDispute(fixture.prior), "actual original judge receipt source is independently required"
  assert origin.disputeInfo.value.entries > 0
  assert origin.reportAt(1).error == AuditOriginError.InvalidIndex
  let target = origin.reportAt(0).value
  assert target.sourceKind == AuditReportSourceKind.Disputed and not target.auditedBlock.present
  assert target.originContext.error == AuditOriginError.InvalidSource
  assert target.originInfo.error == AuditOriginError.InvalidSource
  assert target.auditEpoch.value == uint64(uint32(claim.judgmentRecord.epoch))
  assert target.auditorCount.value == 9
  assert target.routingRosterCount == 2
  assert target.routingRosterEpoch(0).value == 0 and target.routingRosterEpoch(1).value == 0
  assert target.routingPopulation(0).value == 9 and target.routingPopulation(1).value == 9
  assert target.routingRosterEpoch(1).value == target.auditEpoch.value
  assert target.routingRosterEpoch(2).error == AuditOriginError.InvalidIndex, "epoch-zero prior C9 must not invent an epoch minus one"
  let plan = captureAuditFetch(target, fetchLimits()).value
  assert not plan.fetchInfo.value.hasAuditedBlock
  assert plan.fetchInfo.value.assurers == 18 and plan.fetchInfo.value.threshold == 4, "both compatible actual candidate rosters remain queryable; N never guesses their epoch"
  assert array[32, byte](plan.targetAt(true, 0).value.identity) == array[32, byte](
      target.routingValidator(0, 0).value.ed25519)
  assert array[32, byte](plan.targetAt(true, 9).value.identity) == array[32, byte](
      target.routingValidator(1, 0).value.ed25519)
  assert fixture.view.reportAt(target.originReportHash.value, ByteLimit(1000000)).error ==
      ReportReadError.Missing
  assert evaluateDirectAudit(target, [], evaluationLimits()).needsRecovery
  assert captureAuditDisputeOrigin(fixture.prior, support, auditOriginLimits()).error ==
      AuditOriginError.InvalidSource
  var limited = auditOriginLimits()
  limited.valueBytes = ByteLimit(1)
  assert captureAuditDisputeOrigin(fixture.view, support, limited).error ==
      AuditOriginError.LimitExceeded
  assert captureAuditDisputeOrigin(fixture.view, support, auditOriginLimits(),
    assuranceScanControl(stopDispute, nil)).error == AuditOriginError.Cancelled
  let actual = captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(), auditOriginLimits()).value.reportAt(0).value
  var original = -1
  for index in 0..<fixture.bundles.len:
    # Original computed bundles are identified independently of dense availability ordering.
    if array[32, byte](fixture.bundles[index].reportHash) == array[32, byte](
        actual.originReportHash.value): original = index
  assert original >= 0
  let header = target.originReport.value.ownedReportInfo.value.header
  let expected = AvailabilitySpecifier(packageHash: header.packageHash,
    bundleLength: header.bundleLength,
    erasureRoot: header.erasureRoot, erasureShards: header.erasureShards,
    segmentRoot: header.segmentRoot, segmentCount: header.segmentCount)
  let proof = AvailabilityMerkleLimits(bytes: ByteLimit(1000000), hashes: ElementLimit(10000),
      hashBytes: ByteLimit(1000000))
  var packets: seq[VerifiedAvailabilityTransfer] = @[]
  for index in [8, 2, 4, 6]:
    # Maintained proof verification binds every signed descriptor field before actual R=4 reconstruction; no verified owner is retagged.
    let packet = fixture.bundles[original].auditShards[index]
    let verified = verifyAvailabilityTransfer(expected, packet.request, packet.bundleShard,
      packet.segmentShards, packet.justification, proof)
    assert verified.error == AvailabilityTransferError.None
    packets.add(verified.value)
  let recovered = recoverAuditBundle(target, packets, recoveryLimits())
  assert recovered.error == AuditRecoveryError.None
  let evaluated = evaluateRecoveredAudit(target, recovered.value, evaluationLimits())
  assert evaluated.error == AuditEvaluationError.None
  assert evaluated.value.matchesOrigin(target)
  assert not evaluated.value.evaluationInfo.value.positive and
      not evaluated.value.evaluationInfo.value.hasAuditedBlock
  let other = captureAuditDisputeOrigin(fixture.view, support, auditOriginLimits()).value.reportAt(0).value
  assert not target.sameAuditOrigin(other)
  assert evaluateRecoveredAudit(other, recovered.value, evaluationLimits()).error ==
      AuditEvaluationError.InvalidRecovery
  var key = "dispute-key-" & $processId() & ".pem"
  var certificate = "dispute-certificate-" & $processId() & ".pem"
  assuranceSignerFiles(key, certificate, 12)
  defer:
    discard posix.unlink(key.toCString())
    discard posix.unlink(certificate.toCString())
  let signer = loadWorkSigner(certificate, key).value
  let legitimate = supportFixture(fixture).original
  let disputedPositive = actualNegativeClaim(fixture, legitimate)
  let positiveSupport = qualifyJudgmentSupportAt(fixture.view, fixture.blockHash,
    disputedPositive, legitimate.report, actualSupportLimits()).value
  let positiveOrigin = captureAuditDisputeOrigin(fixture.view, positiveSupport, auditOriginLimits()).value.reportAt(0).value
  let reproduced = evaluateDirectAudit(positiveOrigin, fixture.originalWire(positiveOrigin),
      evaluationLimits())
  if reproduced.error != AuditEvaluationError.None:
    echo "disputed positive reproduction refusal ", reproduced.error
    if reproduced.error == AuditEvaluationError.BundleFailure: echo "bundle refusal ",
        reproduced.bundleError.error
    if reproduced.error == AuditEvaluationError.ExecutionFailure: echo "execution refusal ",
        reproduced.executionError.error
  assert reproduced.error == AuditEvaluationError.None and
      reproduced.value.evaluationInfo.value.positive, "a genuinely supported negative claim must still reproduce a valid report positively under actual current execution state"
  assert not reproduced.value.evaluationInfo.value.hasAuditedBlock
  let publicationLimits = AuditPublicationLimits(wireBytes: ByteLimit(100000),
      workspaceBytes: ByteLimit(1000000))
  let publication = prepareAuditPublication(signer, evaluated.value, StateValidatorIndex(1), publicationLimits)
  assert publication.error == AuditPublicationError.None and publication.value.valid
  let rawReply = publication.value.reportReply
  let rawBytes = rawReply.bytes
  assert rawReply.request.kind == ReadKind.Report and rawBytes.len > 4
  let digest = blake2b256(rawBytes.toOpenArray(4, rawBytes.len-1)).value
  assert array[32, byte](digest) == array[32, byte](claim.judgmentRecord.report), "independent hash binds the complete serving body to the genuinely signed report"
  assert qualifyLocalJudgment(publication.value.signedJudgment).value.valid
  assert qualifyLocalJudgment(default(SignedAuditJudgment)).error ==
      JudgmentReceiptError.InvalidSource
  assert prepareAuditPublication(signer, default(AuditEvaluation), StateValidatorIndex(1),
      publicationLimits).error == AuditPublicationError.InvalidEvaluation
  var scarce = publicationLimits
  scarce.wireBytes = ByteLimit(4)
  assert prepareAuditPublication(default(WorkSigner), evaluated.value, StateValidatorIndex(1),
      scarce).error == AuditPublicationError.LimitExceeded, "whole output policy precedes private signing"
  scarce = publicationLimits
  scarce.workspaceBytes = ByteLimit(1)
  assert prepareAuditPublication(signer, evaluated.value, StateValidatorIndex(1), scarce).error ==
      AuditPublicationError.LimitExceeded
  let refused = prepareAuditPublication(signer, evaluated.value, StateValidatorIndex(0), publicationLimits)
  assert refused.error == AuditPublicationError.SigningFailure and refused.signingError.error ==
      AuditSigningError.IdentityMismatch
  assert prepareAuditPublication(signer, evaluated.value, StateValidatorIndex(1), publicationLimits,
      assuranceScanControl(stopDispute, nil)).error == AuditPublicationError.Cancelled
  let signed = signAuditJudgment(signer, evaluated.value, StateValidatorIndex(1))
  assert signed.error == AuditSigningError.None
  let record = signed.value.judgmentRecord
  assert not record.valid and uint32(record.epoch) == uint32(claim.judgmentRecord.epoch)
  assert array[32, byte](record.report) == array[32, byte](claim.judgmentRecord.report)
  assert record.credentialCount == guarantee.credentialCount and uint32(record.slot) == uint32(guarantee.slot)
  let publicKey = EdPublicKey(array[32, byte](target.auditorAt(1).value.ed25519))
  var message: seq[byte] = @[]
  for character in "jam_invalid": message.add(byte(ord(character)))
  for octet in array[32, byte](record.report): message.add(octet)
  assert verify(publicKey, EdSignature(array[64, byte](record.signature)), message), "independent GP domain accepts actual original auditor signature"
