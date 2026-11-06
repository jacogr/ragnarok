# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual PEM/certificate imports, independent literal judgment domains and exact original credentials test private audit signing without a production raw-seed or arbitrary-message interface.
import std/[assertions, monotimes, times, posix/posix]
import ../../src/jamnp-s/[work_signer, audit_evaluation, audit_origin, audit_context, audits]
import ../../src/jamnp-s/assurance_store
import ../../src/app/proof/[worker, work_submission]
import ../../src/codec/[bounded, disputes]
from ../../src/codec/assurances import ValidatorCount
import ../../src/codec/state/safrole
import ../../src/crypto/primitives
import ./[assurance_signer_context, jamnp_audit_context, jamnp_audit_evaluation]
proc processId(): cint {.importc: "getpid", header: "<unistd.h>".}
  ## Names are confined to this test process's native-runner directory.
proc verifySignedAudit*(signed: SignedAuditJudgment, target: AuditReportOrigin, positive: bool) =
  ## Verify raw wire fields and real Ed25519 signatures independently; changing the validity domain or whole report identity must fail.
  assert signed.valid
  let record = signed.judgmentRecord
  let context = target.originContext.value
  let facts = context.contextInfo.value
  assert uint16(record.validator) == 1 and uint32(record.epoch) == facts.epoch and record.valid == positive
  assert array[32, byte](record.report) == array[32, byte](target.originReportHash.value)
  let key = EdPublicKey(array[32, byte](context.auditorAt(1).value.ed25519))
  let domain = if positive: "jam_valid" else: "jam_invalid"
  var message: seq[byte] = @[]
  for octet in domain: message.add(byte(octet))
  for octet in array[32, byte](record.report): message.add(octet)
  let signature = EdSignature(array[64, byte](record.signature))
  assert verify(key, signature, message), "independent pinned GP transcript accepts actual private signature"
  message[0] = message[0] xor 1
  assert not verify(key, signature, message), "different judgment domain cannot reuse the signature"
  message[0] = message[0] xor 1
  message[message.len-1] = message[message.len-1] xor 1
  assert not verify(key, signature, message), "different full report identity cannot reuse the signature"
  message[message.len-1] = message[message.len-1] xor 1
  var epochDomain = @[0'u8, 0, 0, 0]
  for ordinal in 0..<message.len: epochDomain.add(message[ordinal])
  assert not verify(key, signature, epochDomain), "unmerged epoch-prefixed GP proposal is not silently adopted"
  if positive:
    assert record.credentialCount == 0 and uint32(record.slot) == 0, "positive record carries no guarantee"
  else:
    let original = target.originGuarantee.value
    assert record.credentialCount == original.credentialCount and uint32(record.slot) == uint32(
        original.slot), "negative record preserves the exact original admitted slot/quorum"
    for ordinal in 0..<original.credentialCount:
      assert uint16(record.credentials[ordinal].validator) == uint16(original.credentials[
          ordinal].validator)
      assert array[64, byte](record.credentials[ordinal].signature) == array[64, byte](
          original.credentials[ordinal].signature), "original qualified credentials cannot be replaced"
  let limits = AuditLimits(validators: ValidatorCount(uint64(facts.auditors)),
      cores: facts.maximumCores,
    bytes: ByteLimit(306), records: ElementLimit(1))
  let wire = encodeJudgments([record], limits)
  assert wire.error == AuditError.None and wire.value.len == (
      if positive: 103 else: 108+66*record.credentialCount), "exact CE145 record layout"
  let decoded = decodeJudgments(wire.value, limits)
  assert decoded.error == AuditError.None and decoded.value.judgmentAt(0).value.valid == positive, "canonical complete message roundtrip"
proc stopNow(raw: nil pointer): bool {.nimcall, raises: [].} =
  ## Trusted execution cancellation callback has no external graph or production identity injection.
  true
proc auditSigningChecks*(fixture: AuditContextFixture) {.raises.} =
  ## Real positive evaluation, actual key import and fixed native signing preserve exact source/key ownership through cancellation and Done.
  var key = "audit-signing-key-" & $processId() & ".pem"
  var certificate = "audit-signing-certificate-" & $processId() & ".pem"
  assuranceSignerFiles(key, certificate, 12)
  defer:
    discard posix.unlink(key.toCString())
    discard posix.unlink(certificate.toCString())
  let signer = loadWorkSigner(certificate, key).value
  let origin = captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(), auditOriginLimits()).value
  let target = origin.reportAt(0).value
  let evaluated = evaluateDirectAudit(target, fixture.originalWire(target), evaluationLimits()).value
  assert signAuditJudgment(default(WorkSigner), evaluated, StateValidatorIndex(1)).error ==
      AuditSigningError.InvalidSigner
  assert signAuditJudgment(signer, default(AuditEvaluation), StateValidatorIndex(1)).error ==
      AuditSigningError.InvalidEvaluation
  assert signAuditJudgment(signer, evaluated, StateValidatorIndex(1023)).error ==
      AuditSigningError.InvalidValidator
  assert signAuditJudgment(signer, evaluated, StateValidatorIndex(0)).error ==
      AuditSigningError.IdentityMismatch, "local key must match the original prior-C8 ordinal"
  let stopped = signAuditJudgment(signer, evaluated, StateValidatorIndex(1), assuranceScanControl(
      stopNow, nil))
  assert stopped.error == AuditSigningError.Cancelled, "trusted cancellation publishes no signature prefix"
  let signed = signAuditJudgment(signer, evaluated, StateValidatorIndex(1))
  assert signed.error == AuditSigningError.None
  verifySignedAudit(signed.value, target, true)
  var worker = default(StateProofWorker)
  assert worker.start()
  defer:
    worker.close()
  for iteration in 0..1:
    var job = captureAuditSigningJob(signer, evaluated, StateValidatorIndex(1)).value
    let admitted = worker.submit(job)
    assert admitted.error == ProofWorkerError.None and not job.valid
    let deadline = getMonoTime()+initDuration(seconds = 10)
    while worker.phase != ProofWorkerPhase.Done:
      assert getMonoTime() < deadline
    assert worker.collect(default(ProofWorkerTicket)).kind ==
        ProofWorkerCompletionKind.Uninitialized
    if iteration == 0: assert worker.cancel(admitted.value)
    let completed = worker.collect(admitted.value)
    if iteration == 0:
      assert completed.kind == ProofWorkerCompletionKind.Cancelled, "cancelled Done signature is withheld"
    else:
      assert completed.kind == ProofWorkerCompletionKind.WorkSubmitted
      assert completed.workSubmissionValue.kind == WorkJobResultKind.AuditSigned
      verifySignedAudit(completed.workSubmissionValue.signedAudit, target, true)
