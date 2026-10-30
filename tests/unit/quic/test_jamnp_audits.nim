# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Check CE144/145 against independent Python-struct byte witnesses, every prefix, malformed
## tags/indices/guarantees, late failures and immutable capture. Opaque samples are not signatures.

import std/[assertions, envvars, syncio]
import "../../../src/jamnp-s/audits"
import ../../../src/codec/[assurances, bounded, disputes, guarantees]

const Limits = AuditLimits(validators: ValidatorCount(1023), cores: CoreCount(341),
    bytes: ByteLimit(4096), records: ElementLimit(8))

proc fixture(name: string): seq[byte] =
  ## Fixture contract validation binds every member before the native runner starts this suite.
  var text = ""
  try:
    text = readFile(getEnv("RAGNAROK_JAMNP_AUDIT_FIXTURE") & "/" & name & ".bin")
  except:
    quit 2 # Missing frozen input cannot count as successful wire coverage.
  result = newSeq[byte](text.len)
  for i in 0..<text.len: result[i] = byte(text[i])

proc announcements() =
  ## A batch may mix initial and later intents without an outer count or declared tranche.
  var wire = fixture("announcements")
  let decoded = decodeAnnouncements(wire, Limits)
  assert decoded.error == AuditError.None and decoded.value.len == 2
  let owner = decoded.value
  let initial = owner.announcementAt(0).value
  let later = owner.announcementAt(1).value
  assert initial.intent == AuditIntent.Initial and uint16(initial.validator) == 5
  assert later.intent == AuditIntent.Later and uint16(later.validator) == 1022
  assert uint16(later.core) == 340
  # Inspect fixed evidence bytes against independently chosen patterns.
  for i in 0..<32:
    assert array[32, byte](initial.header)[i] == byte(i)
    assert array[32, byte](later.header)[i] == byte(31-i)
  for i in 0..<96:
    assert array[96, byte](initial.proof)[i] == byte(40+i)
    assert array[96, byte](later.proof)[i] == 170
  # Strict prefixes ending at an element boundary are valid shorter batches; all others fail atomically.
  for length in 0..<wire.len:
    let parsed = decodeAnnouncements(wire.toOpenArray(0, length-1), Limits)
    assert (parsed.error == AuditError.None) == (length == 0 or length == 131)
  assert owner.announcementAt(-1).error == AuditError.InvalidIndex
  assert owner.announcementAt(2).error == AuditError.InvalidIndex
  # Mutating caller bytes and detached records cannot change the immutable retained batch.
  for i in 0..<wire.len: wire[i] = 0
  var detached = later
  detached.core = AuditCoreIndex(0)
  assert uint16(owner.announcementAt(1).value.core) == 340
  assert array[32, byte](owner.announcementAt(0).value.header)[31] == 31

proc judgments() =
  ## Distinct epochs/auditors/reports share one batch; invalid guarantees precede the report tail.
  var wire = fixture("judgments")
  let decoded = decodeJudgments(wire, Limits)
  assert decoded.error == AuditError.None and decoded.value.len == 3
  let owner = decoded.value
  let positive = owner.judgmentAt(0).value
  let two = owner.judgmentAt(1).value
  let three = owner.judgmentAt(2).value
  assert positive.valid and uint32(positive.epoch) == 0x01020304'u32
  assert uint16(positive.validator) == 17 and positive.credentialCount == 0
  assert not two.valid and uint32(two.epoch) == 9 and uint16(two.validator) == 18
  assert uint32(two.slot) == 0xaabbccdd'u32 and two.credentialCount == 2
  assert uint16(two.credentials[0].validator) == 2 and uint16(two.credentials[1].validator) == 7
  assert not three.valid and uint32(three.epoch) == 10 and uint16(three.validator) == 19
  assert uint32(three.slot) == 0x11223344'u32 and three.credentialCount == 3
  assert uint16(three.credentials[0].validator) == 0
  assert uint16(three.credentials[1].validator) == 256
  assert uint16(three.credentials[2].validator) == 1022
  for i in 0..<32:
    assert array[32, byte](positive.report)[i] == byte(32+i)
    assert array[32, byte](two.report)[i] == 85
    assert array[32, byte](three.report)[i] == 119
  for i in 0..<64:
    assert array[64, byte](positive.signature)[i] == byte(128+i)
    assert array[64, byte](two.credentials[0].signature)[i] == byte(48+i)
    assert array[64, byte](two.signature)[i] == 102
    assert array[64, byte](three.signature)[i] == 136
  for length in 0..<wire.len:
    let parsed = decodeJudgments(wire.toOpenArray(0, length-1), Limits)
    assert (parsed.error == AuditError.None) == (length == 0 or length == 103 or length == 343)
  assert owner.judgmentAt(-1).error == AuditError.InvalidIndex
  assert owner.judgmentAt(3).error == AuditError.InvalidIndex
  for i in 0..<wire.len: wire[i] = 0
  var detached = two
  detached.credentials[0].validator = GuarantorIndex(500)
  assert uint16(owner.judgmentAt(1).value.credentials[0].validator) == 2

proc encoding() =
  ## Construct encoder sources independently of decoder results, then compare exact wire bytes.
  var initial = AuditAnnouncement(validator: JudgeIndex(5), intent: AuditIntent.Initial)
  var later = AuditAnnouncement(validator: JudgeIndex(1022), intent: AuditIntent.Later,
      core: AuditCoreIndex(340))
  var head0 = default(array[32, byte])
  var head1 = default(array[32, byte])
  var proof0 = default(array[96, byte])
  var proof1 = default(array[96, byte])
  for i in 0..<32:
    head0[i] = byte(i)
    head1[i] = byte(31-i)
  for i in 0..<96:
    proof0[i] = byte(40+i)
    proof1[i] = 170
  initial.header = AuditHeaderHash(head0)
  initial.proof = AuditProof(proof0)
  later.header = AuditHeaderHash(head1)
  later.proof = AuditProof(proof1)
  assert encodeAnnouncements([initial], Limits).value == fixture("initial")
  assert encodeAnnouncements([later], Limits).value == fixture("later")
  assert encodeAnnouncements([initial, later], Limits).value == fixture("announcements")
  var positive = AuditJudgment(epoch: DisputeEpoch(0x01020304'u32), validator: JudgeIndex(17), valid: true)
  var two = AuditJudgment(epoch: DisputeEpoch(9), validator: JudgeIndex(18), valid: false,
      slot: GuaranteeSlot(0xaabbccdd'u32), credentialCount: 2)
  var three = AuditJudgment(epoch: DisputeEpoch(10), validator: JudgeIndex(19), valid: false,
      slot: GuaranteeSlot(0x11223344'u32), credentialCount: 3)
  var report0 = default(array[32, byte])
  var report1 = default(array[32, byte])
  var report2 = default(array[32, byte])
  var signature0 = default(array[64, byte])
  var signature1 = default(array[64, byte])
  var signature2 = default(array[64, byte])
  var credential0 = default(array[64, byte])
  var credential1 = default(array[64, byte])
  for i in 0..<32:
    report0[i] = byte(32+i)
    report1[i] = 85
    report2[i] = 119
  for i in 0..<64:
    signature0[i] = byte(128+i)
    signature1[i] = 102
    signature2[i] = 136
    credential0[i] = byte(48+i)
    credential1[i] = byte(64+i)
  positive.report = DisputeHash(report0)
  positive.signature = DisputeSignature(signature0)
  two.report = DisputeHash(report1)
  two.signature = DisputeSignature(signature1)
  two.credentials[0] = GuaranteeCredential(validator: GuarantorIndex(2),
      signature: GuaranteeSignature(credential0))
  two.credentials[1] = GuaranteeCredential(validator: GuarantorIndex(7),
      signature: GuaranteeSignature(credential1))
  three.report = DisputeHash(report2)
  three.signature = DisputeSignature(signature2)
  for i in 0..<3:
    var signature = default(array[64, byte])
    for j in 0..<64: signature[j] = byte(144+i)
    let index = if i == 0: 0 elif i == 1: 256 else: 1022
    three.credentials[i] = GuaranteeCredential(validator: GuarantorIndex(index),
        signature: GuaranteeSignature(signature))
  assert encodeJudgments([positive], Limits).value == fixture("positive")
  assert encodeJudgments([two], Limits).value == fixture("negative2")
  assert encodeJudgments([three], Limits).value == fixture("negative3")
  assert encodeJudgments([positive, two, three], Limits).value == fixture("judgments")
  # Encoder validation must reject invalid source fields before returning a partially built message.
  initial.validator = JudgeIndex(1023)
  assert encodeAnnouncements([initial], Limits).error == AuditError.InvalidValidator
  later.core = AuditCoreIndex(341)
  assert encodeAnnouncements([later], Limits).error == AuditError.InvalidCore
  positive.credentialCount = 2
  assert encodeJudgments([positive], Limits).error == AuditError.InvalidGuarantee
  two.credentials[1].validator = GuarantorIndex(2)
  assert encodeJudgments([two], Limits).error == AuditError.InvalidGuarantee

proc rejection() =
  ## Late malformed records must poison the whole result rather than publishing a valid prefix.
  var trailing = fixture("announcements")
  trailing.add(0)
  assert decodeAnnouncements(trailing, Limits).error == AuditError.Truncated
  trailing = fixture("judgments")
  trailing.add(0)
  assert decodeJudgments(trailing, Limits).error == AuditError.Truncated
  var announcements = fixture("announcements")
  announcements[131+34] = 2
  assert decodeAnnouncements(announcements, Limits).error == AuditError.InvalidTag
  announcements = fixture("announcements")
  announcements[131+35] = 85
  assert decodeAnnouncements(announcements, Limits).error == AuditError.InvalidCore
  announcements = fixture("announcements")
  announcements[131+32] = 255
  assert decodeAnnouncements(announcements, Limits).error == AuditError.InvalidValidator
  var judgments = fixture("judgments")
  judgments[343+6] = 2
  assert decodeJudgments(judgments, Limits).error == AuditError.InvalidTag
  for count in [0'u8, 1, 4, 128, 255]:
    var wire = fixture("negative2")
    wire[11] = count
    assert decodeJudgments(wire, Limits).error == AuditError.InvalidGuarantee
  var negative = fixture("negative2")
  negative[11] = 3
  assert decodeJudgments(negative, Limits).error == AuditError.Truncated
  negative = fixture("negative2")
  negative[78] = 2
  assert decodeJudgments(negative, Limits).error == AuditError.InvalidGuarantee
  negative = fixture("negative2")
  negative[12] = 255
  negative[13] = 255
  assert decodeJudgments(negative, Limits).error == AuditError.InvalidValidator
  var limits = Limits
  limits.records = ElementLimit(1)
  assert decodeAnnouncements(fixture("announcements"), limits).error == AuditError.LimitExceeded
  assert decodeJudgments(fixture("judgments"), limits).error == AuditError.LimitExceeded
  limits = Limits
  limits.bytes = ByteLimit(130)
  assert decodeAnnouncements(fixture("initial"), limits).error == AuditError.LimitExceeded
  limits.validators = ValidatorCount(0)
  assert decodeJudgments([], limits).error == AuditError.InvalidPolicy
  let emptyAnnouncements = default(AnnouncementBatch)
  let emptyJudgments = default(JudgmentBatch)
  assert emptyAnnouncements.announcementAt(0).error == AuditError.InvalidOwner
  assert emptyJudgments.judgmentAt(0).error == AuditError.InvalidOwner
  let emptyResult = default(AuditResult[AnnouncementBatch])
  assert emptyResult.error == AuditError.Uninitialized

announcements()
judgments()
encoding()
rejection()
echo "JAMNP-S: batched audit wire witnesses, prefixes and immutable records passed"
