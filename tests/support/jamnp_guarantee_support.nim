# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original genuinely admitted credentials and separately signed unpublished reports exercise the narrower guarantee-support boundary without constructing inclusion, availability or computed-success capabilities.

import std/assertions
import ../../src/state/[guarantee_support, guarantors, guarantee_credentials, store]
import ../../src/codec/[bounded, assurances, guarantees, report_owned, owned, disputes]
import ../../src/codec/state/[safrole, consensus, layout, disputes as state_disputes]
import ../../src/codec/work/report
import ../../src/chain/[genesis, provider, parameters, reports]
import ../../src/crypto/[primitives, guarantee]
import ../../src/jamnp-s/[audit_context, audit_origin]
import ./jamnp_audit_context

type SupportFixture* = object ## Only real complete predecessor chapters supply the original assignment planner and its two distinct populations.
  original*: Guarantee
  plan*: GuarantorPlan
  active*, previous*: ValidatorStateSnapshot
  entropy*: StateEntropy
  clock*: StateTime
  offenders*: seq[OffenderKey]
  config*: GuarantorConfig

proc supportLimits*(): GuaranteeSupportLimits =
  ## Complete standalone report/signatures, copied canonical storage and one whole report hash have independent finite credit.
  GuaranteeSupportLimits(wire: GuaranteeConfig(cores: CoreCount(3), validators: ValidatorCount(9),
    maxBytes: ByteLimit(1000000)), workspaceBytes: ByteLimit(8000000),
    hashBytes: ByteLimit(1000000), signatures: ElementLimit(3))

proc supportFixture*(fixture: AuditContextFixture): SupportFixture =
  ## Decode only the actual already published guarantee-inclusion source, without replacing its key tables, entropy or clock.
  let context = captureAuditContext(fixture.view, fixture.blockHash, auditLimits()).value
  let source = fixture.prior.bestBlock.value
  let state = source.stateSnapshot
  let rosters = auditLimits().availability.rosters
  let active = decodeStateValidators(state.lookup(chapterKey(StateChapter(8))).value.bytes,
      rosters).value.value
  let previous = decodeStateValidators(state.lookup(chapterKey(StateChapter(9))).value.bytes,
      rosters).value.value
  let entropy = decodeStateEntropy(state.lookup(chapterKey(StateChapter(
      6))).value.bytes).value.value
  let clock = decodeStateTime(state.lookup(chapterKey(StateChapter(11))).value.bytes).value.value
  let disputes = decodeDisputeState(state.lookup(chapterKey(StateChapter(5))).value.bytes,
    DisputeStateConfig(perSet: ElementLimit(1000), totalItems: ElementLimit(4000),
        maxBytes: ByteLimit(200000))).value.snapshot
  let count = disputes.disputeStateInfo.value.offenders
  var offenders = newSeq[OffenderKey](count)
  for ordinal in 0..<count: offenders[ordinal] = disputes.stateOffenderAt(DisputeStateIndex(uint64(
      ordinal))).value
  let parameters = source.chainParameters
  let config = GuarantorConfig(roster: rosters, epochSlots: EpochSlots(parameters.get(epochPeriod)),
    rotationSlots: GuarantorRotationSlots(parameters.get(rotationPeriod)), offenders: ElementLimit(1000))
  let planned = planGuarantors(active, previous, entropy, clock, offenders, config)
  assert planned.error == GuarantorError.None
  SupportFixture(original: context.auditGuarantee(0).value, plan: planned.value,
    active: active, previous: previous, entropy: entropy, clock: clock, offenders: move(offenders),
        config: config)

proc actualSeed(record: StateValidator): EdSeed =
  ## Match only test-owned private seeds to the actual independently decoded original assigned public key.
  for marker in 1..40:
    var raw = default(array[32, byte])
    raw[0] = byte(marker)
    let seed = importSeed(raw).value
    if array[32, byte](seed.publicKey.value) == array[32, byte](record.ed25519): return seed
  assert false, "actual original fixture key has no test-owned seed"
  return importSeed(default(array[32, byte])).value

proc unseenGuarantee*(source: SupportFixture, wrongPopulation = false, mutation = 1'u8): Guarantee =
  ## Change raw canonical report bytes before genuine original-key signatures. No report admission, C10 mutation or computed-success owner is fabricated.
  let original = source.original.report
  let info = original.ownedReportInfo.value
  var bytes = newSeq[byte](info.consumed)
  assert original.encodeOwnedReport(bytes).error == OwnershipError.None
  if wrongPopulation:
    # Independent fixed header offsets place E2 shard count after package32, length4 and erasure root32.
    bytes[68] = 6
    bytes[69] = 0
  else:
    # A false package identity retains genuine committed original bundle shards for later authenticated forced-audit recovery.
    bytes[0] = bytes[0] xor mutation
  let decoded = decodeOwnedReport(bytes, 3)
  assert decoded.error == OwnershipError.None
  result = source.original
  result.report = decoded.value
  let message = array[45, byte](guaranteeMessage(bytes).value)
  for ordinal in 0..<result.credentialCount:
    # Every raw credential is signed by its exact real original core-assigned key after the report mutation.
    let assigned = source.plan.guarantorAt(result.slot, result.credentials[ordinal].validator).value
    let signed = sign(actualSeed(assigned.validator), message).value
    result.credentials[ordinal].signature = GuaranteeSignature(array[64, byte](signed))

proc guaranteeSupportChecks*(fixture: AuditContextFixture) =
  ## Actual original support, canonical detachment, stale coordinates and a population-mismatched report distinguish signature support from consensus admission.
  let source = supportFixture(fixture)
  let checked = verifyGuaranteeSupport(source.original, source.plan, supportLimits())
  assert checked.error == GuaranteeSupportError.None and checked.value.valid
  let support = checked.value
  assert support.supportInfo.value.credentials == source.original.credentialCount
  for ordinal in 0..<source.original.credentialCount:
    # Original roster positions select copied fixed metadata independently of compressed credential-row order.
    let expected = source.plan.guarantorAt(source.original.slot, source.original.credentials[
        ordinal].validator).value.validator
    assert array[32, byte](support.supportValidator(ordinal).value.ed25519) == array[32, byte](
        expected.ed25519)
  assert support.supportValidator(-1).error == GuaranteeSupportError.InvalidIndex
  assert support.supportValidator(3).error == GuaranteeSupportError.InvalidIndex
  assert verifyGuaranteeSupport(source.original, default(GuarantorPlan), supportLimits()).error ==
      GuaranteeSupportError.AssignmentFailure
  assert verifyGuaranteeSupport(source.original, source.plan, default(
      GuaranteeSupportLimits)).error == GuaranteeSupportError.InvalidPolicy
  assert source.original.credentialCount in 2..3
  var changed = source.original
  var signature = array[64, byte](changed.credentials[changed.credentialCount-1].signature)
  signature[63] = signature[63] xor 1
  changed.credentials[changed.credentialCount-1].signature = GuaranteeSignature(signature)
  assert verifyGuaranteeSupport(changed, source.plan, supportLimits()).error ==
      GuaranteeSupportError.InvalidSignature
  var future = source.original
  assert uint32(source.clock) < high(uint32)
  future.slot = GuaranteeSlot(uint32(source.clock)+1)
  assert verifyGuaranteeSupport(future, source.plan, supportLimits()).error ==
      GuaranteeSupportError.AssignmentFailure
  var limited = supportLimits()
  limited.hashBytes = ByteLimit(1)
  assert verifyGuaranteeSupport(source.original, source.plan, limited).error ==
      GuaranteeSupportError.LimitExceeded
  limited = supportLimits()
  limited.workspaceBytes = ByteLimit(1)
  assert verifyGuaranteeSupport(source.original, source.plan, limited).error ==
      GuaranteeSupportError.LimitExceeded
  let unpublished = unseenGuarantee(source)
  let supported = verifyGuaranteeSupport(unpublished, source.plan, supportLimits())
  assert supported.error == GuaranteeSupportError.None
  let hash = WorkReportHash(array[32, byte](supported.value.supportInfo.value.report))
  assert fixture.view.reportAt(hash, ByteLimit(1000000)).error == ReportReadError.Missing, "standalone signed support does not invent local availability"
  let wrong = unseenGuarantee(source, wrongPopulation = true)
  assert verifyGuaranteeSupport(wrong, source.plan, supportLimits()).error ==
      GuaranteeSupportError.None
  let complete = verifyGuaranteeCredentials([wrong], source.active, source.previous, source.entropy,
    source.clock, source.offenders, GuaranteeCredentialConfig(assignments: source.config,
      maxBytes: ByteLimit(1000000), reporters: ElementLimit(9)))
  assert complete.error == GuaranteeCredentialError.WrongErasureShards, "narrow support cannot bypass the independent full consensus population check"
