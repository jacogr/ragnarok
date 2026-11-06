# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real source-bound standalone negative support uses genuinely published full predecessor state and separately signed unpublished report bytes; no availability assignment or private computation result is fabricated.
import std/assertions
import ../../src/jamnp-s/[audits, judgment_claim, judgment_support, audit_context]
import ../../src/jamnp-s/assurance_store
import ../../src/state/guarantee_support
import ../../src/codec/[bounded, disputes, report_owned, guarantees, assurances]
import ../../src/codec/state/[safrole, disputes as state_disputes]
import ../../src/chain/[genesis, provider]
import ../../src/crypto/primitives
import ./[jamnp_audit_context, jamnp_guarantee_support, jamnp_judgment_claim]
proc actualClaimLimits*(): JudgmentClaimLimits =
  ## The genuine three-core nine-current/six-previous chain keeps its maximum domains distinct from the independent role-seed tests.
  result = claimLimits()
  result.message.cores = CoreCount(3)
  result.message.validators = ValidatorCount(9)
  result.rosters = auditLimits().availability.rosters
proc actualSupportLimits*(): JudgmentSupportLimits =
  ## Every source chapter, actual assignment expansion and output row is reserved before verification.
  JudgmentSupportLimits(support: supportLimits(), rosters: auditLimits().availability.rosters,
    disputes: DisputeStateConfig(perSet: ElementLimit(1000), totalItems: ElementLimit(4000),
        maxBytes: ByteLimit(200000)),
    readBytes: ByteLimit(4000000), workspaceBytes: ByteLimit(64000000), retainedBytes: ByteLimit(
        4000000),
    hashBytes: ByteLimit(8000000), hashes: ElementLimit(4096))
proc actualNegativeClaim*(fixture: AuditContextFixture, guarantee: Guarantee): SignedJudgmentClaim =
  ## A real original auditor signs the hash of separately certified raw work, while supporting credentials stay outside the GP judgment signature domain.
  let source = supportFixture(fixture)
  let supported = verifyGuaranteeSupport(guarantee, source.plan, supportLimits()).value
  let hash = supported.supportInfo.value.report
  var raw = default(array[32, byte])
  raw[0] = 12
  let seed = importSeed(raw).value
  let context = captureAuditContext(fixture.view, fixture.blockHash, auditLimits()).value
  assert array[32, byte](seed.publicKey.value) == array[32, byte](context.auditorAt(
      1).value.ed25519)
  var message: seq[byte] = @[]
  for character in "jam_invalid": message.add(byte(ord(character)))
  for octet in array[32, byte](hash): message.add(octet)
  let record = AuditJudgment(epoch: DisputeEpoch(context.contextInfo.value.epoch),
    validator: JudgeIndex(1), valid: false, report: hash,
    signature: DisputeSignature(array[64, byte](sign(seed, message).value)),
    slot: guarantee.slot, credentialCount: guarantee.credentialCount,
        credentials: guarantee.credentials)
  let wire = encodeJudgments([record], actualClaimLimits().message).value
  let checked = verifyJudgmentClaims(fixture.view, wire, actualClaimLimits())
  assert checked.error == JudgmentClaimError.None
  checked.value.claimAt(0).value
proc stopSupport(raw: nil pointer): bool {.nimcall, raises: [].} =
  ## Execution-only cancellation stores no caller closure in a queued source job.
  true
proc judgmentSupportChecks*(fixture: AuditContextFixture) =
  ## Unknown report support must match every real original credential and actual independently selected source; metadata copies cannot substitute an availability block.
  let source = supportFixture(fixture)
  let guarantee = unseenGuarantee(source)
  let claim = actualNegativeClaim(fixture, guarantee)
  let selected = fixture.prior.bestBlock.value
  let checked = qualifyJudgmentSupportAt(fixture.view, selected.blockHash, claim, guarantee.report,
      actualSupportLimits())
  assert checked.error == JudgmentSupportError.None and checked.value.valid
  let support = checked.value
  assert support.matchesSource(fixture.prior.bestBlock) and not support.matchesSource(
      fixture.view.bestBlock)
  assert array[32, byte](support.supportInfo.value.report) == array[32, byte](
      claim.judgmentRecord.report)
  assert support.supportInfo.value.auditEpoch == uint64(uint32(claim.claimInfo.epoch))
  assert support.supportInfo.value.auditors == 9 and support.supportInfo.value.current == 9 and
      support.supportInfo.value.previous == 6
  assert support.supportCertificate.value.supportedGuarantee.value.credentialCount ==
      guarantee.credentialCount
  assert support.supportAuditors.value.validatorCount.value == claim.claimInfo.population
  var copied = support.supportInfo.value
  copied.auditEpoch = copied.auditEpoch+1
  assert support.supportInfo.value.auditEpoch != copied.auditEpoch, "public observations cannot retag original auditor authority"
  let unknown = genesis.BlockHash(default(array[32, byte]))
  assert qualifyJudgmentSupportAt(fixture.view, unknown, claim, guarantee.report,
      actualSupportLimits()).error == JudgmentSupportError.UnknownSource
  assert qualifyJudgmentSupportAt(fixture.view, selected.blockHash, default(SignedJudgmentClaim),
      guarantee.report, actualSupportLimits()).error == JudgmentSupportError.InvalidClaim
  assert qualifyJudgmentSupportAt(fixture.view, selected.blockHash, claim, guarantee.report,
      default(JudgmentSupportLimits)).error == JudgmentSupportError.InvalidPolicy
  assert qualifyJudgmentSupportAt(fixture.view, selected.blockHash, claim, source.original.report,
      actualSupportLimits()).error == JudgmentSupportError.SupportFailure, "a different full report cannot inherit the inline guarantee signatures"
  var limited = actualSupportLimits()
  limited.readBytes = ByteLimit(1)
  assert qualifyJudgmentSupportAt(fixture.view, selected.blockHash, claim, guarantee.report,
      limited).error == JudgmentSupportError.LimitExceeded
  limited = actualSupportLimits()
  limited.hashes = ElementLimit(1)
  assert qualifyJudgmentSupportAt(fixture.view, selected.blockHash, claim, guarantee.report,
      limited).error == JudgmentSupportError.LimitExceeded
  limited = actualSupportLimits()
  limited.retainedBytes = ByteLimit(1)
  assert qualifyJudgmentSupportAt(fixture.view, selected.blockHash, claim, guarantee.report,
      limited).error == JudgmentSupportError.LimitExceeded
  let cancelled = qualifyJudgmentSupportAt(fixture.view, selected.blockHash, claim,
    guarantee.report, actualSupportLimits(), assuranceScanControl(stopSupport, nil))
  assert cancelled.error == JudgmentSupportError.Cancelled
