## Native disputes default/variant, owner lifetime, atomicity and nested-alias regressions.
import ../../src/codec/[disputes, bounded, assurances]

# Test-only success selection makes every expected-good getter check its failure branch explicitly.
proc checked[T](parsed: DisputeResult[T]): T =
  doAssert parsed.error == DisputeError.None
  parsed.value

let config = DisputeConfig(validators: ValidatorCount(1023), maxBytes: ByteLimit(2097152))
var value = Disputes(verdicts: @[Verdict(epoch: DisputeEpoch(42),
    judgments: @[Judgment(valid: true, judge: JudgeIndex(2))])],
  culprits: @[Culprit()], faults: @[Fault(valid: true)])
var output: array[512, byte]
let encoded = encodeDisputes(value, config, output)
doAssert encoded.error == DisputeError.None
let parsed = decodeDisputes(output.toOpenArray(0, encoded.value-1), config)
doAssert parsed.error == DisputeError.None and parsed.value.info.verdicts == 1
# Destroy source contents and retain the owner through independent ARC handles.
var retained = parsed.value.owner
for i in 0..<output.len: output[i] = 0
value.verdicts[0].judgments[0].judge = JudgeIndex(7)
doAssert uint16(checked(judgmentAt(retained, 0, 0)).judge) == 2
let retainedCopy = retained
retained = OwnedDisputes()
doAssert uint32(checked(verdictAt(retainedCopy, 0)).epoch) == 42
# Invalid handles and indices never manufacture usable metadata, records or progress.
doAssert disputesInfo(retained).error == DisputeError.InvalidOwner
doAssert verdictAt(retained, 0).error == DisputeError.InvalidOwner
doAssert judgmentAt(retained, 0, 0).error == DisputeError.InvalidOwner
doAssert culpritAt(retained, 0).error == DisputeError.InvalidOwner
doAssert faultAt(retained, 0).error == DisputeError.InvalidOwner
doAssert encodeOwnedDisputes(retained, output).error == DisputeError.InvalidOwner
doAssert judgmentAt(retainedCopy, -1, 0).error == DisputeError.InvalidIndex
doAssert judgmentAt(retainedCopy, 0, -1).error == DisputeError.InvalidIndex
doAssert judgmentAt(retainedCopy, 0, 1).error == DisputeError.InvalidIndex
# A last-section ordering error must preserve all earlier potential output, including a zero-capacity call.
value.faults.add(Fault())
for i in 0..<output.len: output[i] = 0xA5
let bad = encodeDisputes(value, config, output)
doAssert bad.error == DisputeError.NonCanonical
for octet in output: doAssert octet == 0xA5 # No prefix writes precede late source validation.
var empty: seq[byte]
doAssert encodeDisputes(value, config, empty).error == DisputeError.NonCanonical
value.faults.setLen(1)
# A short destination is unchanged both for borrowed sources and immutable owner re-emission.
doAssert encodeDisputes(value, config, output.toOpenArray(0, 1)).error ==
    DisputeError.OutputTooSmall
doAssert encodeOwnedDisputes(retainedCopy, output.toOpenArray(0, 1)).error ==
    DisputeError.OutputTooSmall
for octet in output: doAssert octet == 0xA5 # Rejected capacities preserve every caller byte.
# Real oversized typed allocations provide legal backing extents for alias tests, without out-of-bounds fixtures.
value.verdicts = newSeq[Verdict](16)
for i in 0..<16:
  var target: array[32, byte]
  target[31] = byte(i)
  value.verdicts[i].target = DisputeHash(target) # Ascending identities keep source policy valid.
value.culprits.setLen(0)
value.faults.setLen(0)
# Bare verdicts need 595 wire bytes; sixteen real records provide enough backing storage for that extent.
let verdictExtent = 3+16*37
doAssert sizeof(Verdict)*value.verdicts.len >= verdictExtent
let verdictBytes = cast[ptr UncheckedArray[byte]](addr value.verdicts[0])
doAssert encodeDisputes(value, config, verdictBytes.toOpenArray(0, verdictExtent-1)).error ==
    DisputeError.AliasedBuffers
# A destination into a nested judgment sequence must be rejected before writing the outer header.
var aliasVotes = newSeq[Judgment](1023)
for i in 0..<1023: aliasVotes[i].judge = JudgeIndex(i) # Full bounded count remains canonical.
var laterTarget: array[32, byte]
laterTarget[31] = 1
value = Disputes(verdicts: @[Verdict(), Verdict(target: DisputeHash(laterTarget),
    judgments: aliasVotes)])
# Use the actual source allocation: Nim sequence assignment can copy the original construction sequence.
let nestedLength = 3+37+36+2+67*1023
if sizeof(Judgment)*value.verdicts[1].judgments.len >= nestedLength:
  # Supported native ABIs align Judgment's E2 field, leaving sufficient genuine padding.
  let bytes = cast[ptr UncheckedArray[byte]](addr value.verdicts[1].judgments[0])
  doAssert encodeDisputes(value, config, bytes.toOpenArray(0, nestedLength-1)).error ==
      DisputeError.AliasedBuffers
else:
  # A packed ABI still runs outer-record alias checks without inventing backing bytes.
  doAssert sizeof(Judgment) == 67
# Shrinking fixed records preserves real backing capacity for a destination including its three count bytes.
value = Disputes(culprits: newSeq[Culprit](17))
value.culprits.setLen(16)
for i in 0..<16:
  var key: array[32, byte]
  key[31] = byte(i)
  value.culprits[i].key = OffenderKey(key) # Ordering remains valid while testing physical storage overlap.
let culpritBytes = cast[ptr UncheckedArray[byte]](addr value.culprits[0])
doAssert encodeDisputes(value, config, culpritBytes.toOpenArray(0, 3+16*128-1)).error ==
    DisputeError.AliasedBuffers
# Faults have an extra Boolean byte but the same actual-capacity fixture strategy.
value = Disputes(faults: newSeq[Fault](17))
value.faults.setLen(16)
for i in 0..<16:
  var key: array[32, byte]
  key[31] = byte(i)
  value.faults[i].key = OffenderKey(key) # Only canonical sources reach the alias gate.
let faultBytes = cast[ptr UncheckedArray[byte]](addr value.faults[0])
doAssert encodeDisputes(value, config, faultBytes.toOpenArray(0, 3+16*129-1)).error ==
    DisputeError.AliasedBuffers
# The caller's outer sequence descriptors also count as source storage, even for empty sections.
value = Disputes()
let descriptors = cast[ptr UncheckedArray[byte]](addr value)
doAssert encodeDisputes(value, config, descriptors.toOpenArray(0, 2)).error ==
    DisputeError.AliasedBuffers
# Optimized ARC builds must keep the success-branch field guard for malformed/default results.
var guarded = false
try:
  discard decodeDisputes(@[255'u8], config).value.info
except FieldDefect:
  guarded = true # Invalid success access must trap instead of returning default progress.
doAssert guarded
var absentResult: DisputeResult[int]
doAssert absentResult.error == DisputeError.Uninitialized
# Canonical empty disputes retain three count bytes and an initialized owner.
let emptyResult = decodeDisputes(@[0'u8, 0, 0], config)
doAssert emptyResult.error == DisputeError.None and emptyResult.value.info.consumed == 3

echo "Nim disputes: owner lifetime, guarded results, atomicity and aliases passed"
