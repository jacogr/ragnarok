# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently signed raw CE145 messages use explicitly trusted genesis key-role seeds. These fixtures test original membership/signature claims, not block execution, guarantee qualification or report validity.
import std/assertions
import ../../src/jamnp-s/[audits, judgment_claim, assurance_store]
import ../../src/codec/[bounded, disputes, guarantees, assurances]
import ../../src/codec/state/safrole
import ../../src/chain/[genesis, provider]
import ../../src/crypto/primitives
import ./jamnp_topology_fixture
proc claimLimits*(): JudgmentClaimLimits =
  ## One maximum mixed-epoch batch has independent finite whole-read, scratch, output and Ed25519 transcript credits.
  JudgmentClaimLimits(message: AuditLimits(validators: ValidatorCount(12), cores: CoreCount(4),
    bytes: ByteLimit(4896), records: ElementLimit(16)),
    rosters: topologyLimits().validators, readBytes: ByteLimit(1000000),
    workspaceBytes: ByteLimit(16000000), retainedBytes: ByteLimit(64000),
    signatures: ElementLimit(16), signatureBytes: ByteLimit(688))
proc claimRoster(first, count: int): seq[StateValidator] =
  ## Real test-owned Ed25519 seeds populate a trusted key-role source before any incoming claim is verified.
  result = newSeq[StateValidator](count)
  for ordinal in 0..<count:
    var seed = default(array[32, byte])
    seed[0] = byte(first+ordinal)
    result[ordinal] = StateValidator(ed25519: StateEdKey(array[32, byte](
      publicKey(importSeed(seed).value).value)))
proc claimView*(repeated = false, nulled = false, atSlot = 13'u32): ChainView =
  ## A configured genesis key-role source explicitly has current six and previous nine validators; it makes no claim of a computed epoch transition.
  var current = claimRoster(21, 6)
  if repeated: current[1] = current[0]
  if nulled: current[1] = nullValidator()
  let previous = claimRoster(1, 9)
  let next = claimRoster(41, 6)
  let source = topologyCaptured([previous, current, next], atSlot = atSlot)
  assert source.error == GenesisError.None
  genesisView(source)
proc rawClaim*(epoch: uint32, validator: uint16, marker: byte, positive = true,
    hashMarker = 71'u8): AuditJudgment =
  ## Malicious or honest network records can be signed independently of evaluation; only the actual signature claim is certified by this test.
  var hash = default(array[32, byte])
  hash[0] = hashMarker
  result = AuditJudgment(epoch: DisputeEpoch(epoch), validator: JudgeIndex(validator),
    valid: positive, report: DisputeHash(hash))
  if not positive:
    # Structural zero signatures deliberately remain unqualified supporting credentials after judge signature authentication.
    result.slot = GuaranteeSlot(1)
    result.credentialCount = 2
    result.credentials[0] = GuaranteeCredential(validator: GuarantorIndex(0))
    result.credentials[1] = GuaranteeCredential(validator: GuarantorIndex(1))
  var seed = default(array[32, byte])
  seed[0] = marker
  var message: seq[byte] = @[]
  let domain = if positive: "jam_valid" else: "jam_invalid"
  for character in domain: message.add(byte(ord(character)))
  for octet in hash: message.add(octet)
  result.signature = DisputeSignature(array[64, byte](sign(importSeed(seed).value, message).value))
proc claimWire*(records: openArray[AuditJudgment]): seq[byte] =
  ## Encode only structurally well-formed complete records; the codec never grants a cryptographic capability.
  let wire = encodeJudgments(records, claimLimits().message)
  assert wire.error == AuditError.None
  wire.value
proc stopClaim(raw: nil pointer): bool {.nimcall, raises: [].} =
  ## Trusted execution-only cancellation retains no user callback graph.
  true
proc judgmentClaimChecks*() =
  ## Different original populations, exact GP domains, unqualified negative credentials, repeated/null positions and late failure all use actual Ed25519 verification.
  let view = claimView()
  let current = rawClaim(1, 5, 26)
  let previous = rawClaim(0, 8, 9, hashMarker = 72)
  let negative = rawClaim(1, 0, 21, positive = false, hashMarker = 73)
  let wire = claimWire([current, previous, negative])
  let checked = verifyJudgmentClaims(view, wire, claimLimits())
  assert checked.error == JudgmentClaimError.None and checked.value.len == 3
  let batch = checked.value
  assert batch.claimAt(0).value.claimInfo.population == 6
  assert batch.claimAt(1).value.claimInfo.population == 9, "previous index eight must not be checked against current six or compressed"
  assert not batch.claimAt(2).value.judgmentRecord.valid
  assert batch.claimAt(2).value.judgmentRecord.credentialCount == 2, "judge authentication alone leaves raw supporting signatures unqualified"
  var copied = batch.claimAt(0).value.judgmentRecord
  copied.valid = false
  copied.validator = JudgeIndex(0)
  assert batch.claimAt(0).value.judgmentRecord.valid and uint16(batch.claimAt(
      0).value.claimInfo.validator) == 5
  assert batch.claimAt(-1).error == JudgmentClaimError.InvalidIndex
  assert batch.claimAt(3).error == JudgmentClaimError.InvalidIndex
  assert not default(SignedJudgmentClaim).valid and not default(SignedJudgmentBatch).valid
  assert verifyJudgmentClaims(genesisView(unavailableGenesis()), wire, claimLimits()).error ==
      JudgmentClaimError.InvalidSource
  assert verifyJudgmentClaims(view, wire, default(JudgmentClaimLimits)).error ==
      JudgmentClaimError.InvalidPolicy
  let wrongIndex = rawClaim(1, 8, 9)
  assert verifyJudgmentClaims(view, claimWire([current, wrongIndex]), claimLimits()).error ==
      JudgmentClaimError.InvalidAuditor, "an existing previous ordinal cannot substitute a current index"
  let wrongEpoch = rawClaim(2, 5, 26)
  assert verifyJudgmentClaims(view, claimWire([current, wrongEpoch]), claimLimits()).error ==
      JudgmentClaimError.UnknownEpoch
  assert verifyJudgmentClaims(claimView(atSlot = 1), claimWire([rawClaim(high(uint32), 0, 21)]),
      claimLimits()).error == JudgmentClaimError.UnknownEpoch, "epoch zero must not underflow to an ancient roster"
  var damaged = previous
  var signature = array[64, byte](damaged.signature)
  signature[63] = signature[63] xor 1
  damaged.signature = DisputeSignature(signature)
  let lateBad = verifyJudgmentClaims(view, claimWire([current, damaged]), claimLimits())
  assert lateBad.error == JudgmentClaimError.InvalidSignature, "a late bad signature publishes no accepted prefix"
  var incomplete = wire
  incomplete.setLen(incomplete.len-1)
  assert verifyJudgmentClaims(view, incomplete, claimLimits()).error ==
      JudgmentClaimError.DecodeFailure
  var limited = claimLimits()
  limited.signatures = ElementLimit(2)
  assert verifyJudgmentClaims(view, wire, limited).error == JudgmentClaimError.LimitExceeded
  limited = claimLimits()
  limited.signatureBytes = ByteLimit(42)
  assert verifyJudgmentClaims(view, claimWire([current]), limited).error ==
      JudgmentClaimError.LimitExceeded
  limited = claimLimits()
  limited.retainedBytes = ByteLimit(1)
  assert verifyJudgmentClaims(view, wire, limited).error == JudgmentClaimError.LimitExceeded
  limited = claimLimits()
  limited.workspaceBytes = ByteLimit(1)
  assert verifyJudgmentClaims(view, wire, limited).error == JudgmentClaimError.LimitExceeded
  let cancelled = verifyJudgmentClaims(view, wire, claimLimits(), assuranceScanControl(stopClaim, nil))
  assert cancelled.error == JudgmentClaimError.Cancelled
  let aliases = claimWire([rawClaim(1, 0, 21), rawClaim(1, 1, 21)])
  let repeated = verifyJudgmentClaims(claimView(repeated = true), aliases, claimLimits())
  assert repeated.error == JudgmentClaimError.None and repeated.value.len == 2
  assert uint16(repeated.value.claimAt(0).value.claimInfo.validator) == 0 and
    uint16(repeated.value.claimAt(1).value.claimInfo.validator) == 1, "identical keys retain each original positional namespace"
  assert verifyJudgmentClaims(claimView(nulled = true), aliases, claimLimits()).error ==
      JudgmentClaimError.InvalidAuditor
proc judgmentClaimCycle*(view: ChainView, wire: seq[byte]) =
  ## Whole checked batches and their fixed records release without retaining canonical state between iterations.
  let checked = verifyJudgmentClaims(view, wire, claimLimits())
  assert checked.error == JudgmentClaimError.None and checked.value.len == 2
