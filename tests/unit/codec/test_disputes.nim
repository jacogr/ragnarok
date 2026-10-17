## Native disputes default/variant, owner lifetime, atomicity and nested-alias regressions.
import ../../support/arc_evidence
import std/[assertions, syncio]
import ../../../src/codec/[disputes, bounded, assurances]

# Test-only success selection makes every expected-good getter check its failure branch explicitly.
proc checked[T](parsed: DisputeResult[T]): T =
  assert parsed.error == DisputeError.None
  parsed.value

let config = DisputeConfig(validators: ValidatorCount(1023), maxBytes: ByteLimit(2097152))
var value = Disputes(verdicts: @[Verdict(epoch: DisputeEpoch(42),
    judgments: @[Judgment(valid: true, judge: JudgeIndex(2))])],
  culprits: @[Culprit()], faults: @[Fault(valid: true)])
var output: array[512, byte] = default(array[512, byte])
let encoded = encodeDisputes(value, config, output)
assert encoded.error == DisputeError.None
let parsed = decodeDisputes(output.toOpenArray(0, encoded.value-1), config)
assert parsed.error == DisputeError.None and parsed.value.info.verdicts == 1
# Destroy source contents and retain the owner through independent ARC handles.
var retained = parsed.value.owner
for i in 0..<output.len: output[i] = 0
value.verdicts[0].judgments[0].judge = JudgeIndex(7)
assert uint16(checked(judgmentAt(retained, 0, 0)).judge) == 2
let retainedCopy = retained
retained = OwnedDisputes()
assert uint32(checked(verdictAt(retainedCopy, 0)).epoch) == 42
# Invalid handles and indices never manufacture usable metadata, records or progress.
assert disputesInfo(retained).error == DisputeError.InvalidOwner
assert verdictAt(retained, 0).error == DisputeError.InvalidOwner
assert judgmentAt(retained, 0, 0).error == DisputeError.InvalidOwner
assert culpritAt(retained, 0).error == DisputeError.InvalidOwner
assert faultAt(retained, 0).error == DisputeError.InvalidOwner
assert encodeOwnedDisputes(retained, output).error == DisputeError.InvalidOwner
assert judgmentAt(retainedCopy, -1, 0).error == DisputeError.InvalidIndex
assert judgmentAt(retainedCopy, 0, -1).error == DisputeError.InvalidIndex
assert judgmentAt(retainedCopy, 0, 1).error == DisputeError.InvalidIndex
# A last-section ordering error must preserve all earlier potential output, including a zero-capacity call.
value.faults.add(Fault())
for i in 0..<output.len: output[i] = 0xA5
let bad = encodeDisputes(value, config, output)
assert bad.error == DisputeError.NonCanonical
for octet in output: assert octet == 0xA5 # No prefix writes precede late source validation.
var empty: seq[byte] = default(seq[byte])
assert encodeDisputes(value, config, empty).error == DisputeError.NonCanonical
value.faults.setLen(1)
# A short destination is unchanged both for borrowed sources and immutable owner re-emission.
assert encodeDisputes(value, config, output.toOpenArray(0, 1)).error ==
    DisputeError.OutputTooSmall
assert encodeOwnedDisputes(retainedCopy, output.toOpenArray(0, 1)).error ==
    DisputeError.OutputTooSmall
for octet in output: assert octet == 0xA5 # Rejected capacities preserve every caller byte.
# Real oversized typed allocations provide legal backing extents for alias tests, without out-of-bounds fixtures.
value.verdicts = newSeq[Verdict](16)
for i in 0..<16:
  var target: array[32, byte] = default(array[32, byte])
  target[31] = byte(i)
  value.verdicts[i].target = DisputeHash(target) # Ascending identities keep source policy valid.
value.culprits.setLen(0)
value.faults.setLen(0)
# Bare verdicts need 595 wire bytes; sixteen real records provide enough backing storage for that extent.
let verdictExtent = 3+16*37
assert sizeof(Verdict)*value.verdicts.len >= verdictExtent
let verdictBytes = cast[ptr array[16*sizeof(Verdict), byte]](addr value.verdicts[0])
assert encodeDisputes(value, config, verdictBytes[].toOpenArray(0, verdictExtent-1)).error ==
    DisputeError.AliasedBuffers
# A destination into a nested judgment sequence must be rejected before writing the outer header.
var aliasVotes = newSeq[Judgment](1023)
for i in 0..<1023: aliasVotes[i].judge = JudgeIndex(i) # Full bounded count remains canonical.
var laterTarget: array[32, byte] = default(array[32, byte])
laterTarget[31] = 1
value = Disputes(verdicts: @[Verdict(), Verdict(target: DisputeHash(laterTarget),
    judgments: aliasVotes)])
# Use the actual source allocation: Nim sequence assignment can copy the original construction sequence.
let nestedLength = 3+37+36+2+67*1023
if sizeof(Judgment)*value.verdicts[1].judgments.len >= nestedLength:
  # Supported native ABIs align Judgment's E2 field, leaving sufficient genuine padding.
  let bytes = cast[ptr array[1023*sizeof(Judgment), byte]](addr value.verdicts[1].judgments[0])
  assert encodeDisputes(value, config, bytes[].toOpenArray(0, nestedLength-1)).error ==
      DisputeError.AliasedBuffers
else:
  # A packed ABI still runs outer-record alias checks without inventing backing bytes.
  assert sizeof(Judgment) == 67
# Shrinking fixed records preserves real backing capacity for a destination including its three count bytes.
value = Disputes(culprits: newSeq[Culprit](17))
value.culprits.setLen(16)
for i in 0..<16:
  var key: array[32, byte] = default(array[32, byte])
  key[31] = byte(i)
  value.culprits[i].key = OffenderKey(key) # Ordering remains valid while testing physical storage overlap.
let culpritBytes = cast[ptr array[17*sizeof(Culprit), byte]](addr value.culprits[0])
assert encodeDisputes(value, config, culpritBytes[].toOpenArray(0, 3+16*128-1)).error ==
    DisputeError.AliasedBuffers
# Faults have an extra Boolean byte but the same actual-capacity fixture strategy.
value = Disputes(faults: newSeq[Fault](17))
value.faults.setLen(16)
for i in 0..<16:
  var key: array[32, byte] = default(array[32, byte])
  key[31] = byte(i)
  value.faults[i].key = OffenderKey(key) # Only canonical sources reach the alias gate.
let faultBytes = cast[ptr array[17*sizeof(Fault), byte]](addr value.faults[0])
assert encodeDisputes(value, config, faultBytes[].toOpenArray(0, 3+16*129-1)).error ==
    DisputeError.AliasedBuffers
# The caller's outer sequence descriptors also count as source storage, even for empty sections.
value = Disputes()
let descriptors = cast[ptr array[sizeof(Disputes), byte]](addr value)
assert encodeDisputes(value, config, descriptors[].toOpenArray(0, 2)).error ==
    DisputeError.AliasedBuffers
# Invalid success access is verified through independent processes matching Nimony contract diagnostics.
assert decodeDisputes(@[255'u8], config).error == DisputeError.Truncated
var absentResult: DisputeResult[int] = default(DisputeResult[int])
assert absentResult.error == DisputeError.Uninitialized
# Canonical empty disputes retain three count bytes and an initialized owner.
let emptyResult = decodeDisputes(@[0'u8, 0, 0], config)
assert emptyResult.error == DisputeError.None and emptyResult.value.info.consumed == 3

# Capture a complete three-section snapshot from local typed sources and stack wire storage.
proc capture(marker: byte): OwnedDisputes =
  var identity = default(array[32, byte])
  identity[0] = marker
  var signature = default(array[64, byte])
  signature[63] = marker
  var sources = Disputes(verdicts: @[Verdict(target: DisputeHash(identity), epoch: DisputeEpoch(
      uint32(marker)),
    judgments: @[Judgment(valid: true, judge: JudgeIndex(2), signature: DisputeSignature(
        signature))])],
    culprits: @[Culprit(target: DisputeHash(identity), key: OffenderKey(identity),
        signature: DisputeSignature(signature))],
    faults: @[Fault(target: DisputeHash(identity), valid: true, key: OffenderKey(identity),
        signature: DisputeSignature(signature))])
  var wire = default(array[1024, byte])
  let encoded = encodeDisputes(sources, config, wire)
  assert encoded.error == DisputeError.None
  let captured = decodeDisputes(wire.toOpenArray(0, encoded.value-1), config)
  assert captured.error == DisputeError.None
  # Original sequences, local identity/signature buffers and wire bytes are irrelevant after capture.
  sources.verdicts[0].judgments[0].judge = JudgeIndex(7)
  identity[0] = marker xor 255
  signature[63] = marker xor 255
  for octet in wire.mitems: octet = 0
  captured.value.owner

# A retained alias outlives replacement and both original source scopes, with same-sized distinct snapshots.
proc escaped(marker: byte): OwnedDisputes =
  var original = capture(marker)
  let retained = original
  original = capture(marker xor 255)
  assert array[32, byte](checked(verdictAt(original, 0)).target)[0] == (marker xor 255)
  retained

# Every scope queries all record families, mutates independent copies, then drops every ARC reference.
proc releaseCycle(marker: byte) =
  let owner = escaped(marker)
  var info = checked(disputesInfo(owner))
  assert info.verdicts == 1 and info.culprits == 1 and info.faults == 1
  info.verdicts = 0
  assert checked(disputesInfo(owner)).verdicts == 1
  let verdict = checked(verdictAt(owner, 0))
  assert uint32(verdict.epoch) == uint32(marker) and verdict.judgments == 1
  assert array[32, byte](verdict.target)[0] == marker
  var vote = checked(judgmentAt(owner, 0, 0))
  assert vote.valid and uint16(vote.judge) == 2
  assert array[64, byte](vote.signature)[63] == marker
  vote.valid = false
  assert checked(judgmentAt(owner, 0, 0)).valid
  var culprit = checked(culpritAt(owner, 0))
  assert array[32, byte](culprit.key)[0] == marker
  culprit.key = OffenderKey(default(array[32, byte]))
  assert array[32, byte](checked(culpritAt(owner, 0)).key)[0] == marker
  var fault = checked(faultAt(owner, 0))
  assert fault.valid and array[64, byte](fault.signature)[63] == marker
  fault.valid = false
  assert checked(faultAt(owner, 0)).valid
  var wire = default(array[1024, byte])
  assert checked(encodeOwnedDisputes(owner, wire)) == checked(disputesInfo(owner)).consumed
  assert wire[1] == marker

# Warm up public live-memory accounting before measuring isolated retain/replace/drop cycles.
for i in 0..<100: releaseCycle(byte(i mod 256))
let beforeRelease = getOccupiedMem()
# Vary source bytes while all local sequences, copies and owner aliases die before each observation.
for i in 0..<1000: releaseCycle(byte(i mod 256))
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve raw measurements outside the platform-independent completion output.
recordArcRelease("disputes", 1000, beforeRelease, afterRelease)
echo "DISPUTE_ARC_RELEASE cycles=1000 unchanged"
echo "Disputes: retained replacement, all record copies, atomicity, aliases and ARC release passed"
