## Native guarantee owner, late-failure, alias and default-result safety checks.
import std/os
import ../../src/codec/[guarantees, report_owned, owned, bounded, assurances]

# Copy a fixture file into explicit owned octets without type-punning a mutable string.
proc bytes(path: string): seq[byte] =
  let text = readFile(path)
  result = newSeq[byte](text.len)
  # Every byte belongs to this test input and can safely be mutated after capture.
  for i in 0..<text.len: result[i] = byte(text[i])

let limits = GuaranteeConfig(cores: CoreCount(341), validators: ValidatorCount(1023),
    maxBytes: ByteLimit(1048576))
var wire = bytes(paramStr(1))
let first = decodeOwnedReport(wire, 341)
doAssert first.error == OwnershipError.None
# The authored fixture has no prerequisites and a one-byte core at the known C.2 offset.
doAssert wire[272] == 0 and wire[273] == 0
wire[273] = 1
let second = decodeOwnedReport(wire, 341)
doAssert second.error == OwnershipError.None
var values: array[8, Guarantee]
# Two strictly increasing cores create a valid composed source with later-record failure opportunities.
for i in 0..<2:
  values[i] = Guarantee(report: if i == 0: first.value else: second.value,
    slot: GuaranteeSlot(uint32(i+1)), credentialCount: 2)
  values[i].credentials[0].validator = GuarantorIndex(0)
  values[i].credentials[1].validator = GuarantorIndex(1)
var output: array[4096, byte]
let encoded = encodeGuarantees(values.toOpenArray(0, 1), limits, output)
doAssert encoded.error == GuaranteeError.None
let captured = decodeGuarantees(output.toOpenArray(0, encoded.value-1), limits)
doAssert captured.error == GuaranteeError.None and captured.value.count == 2
# Caller source mutations cannot change retained report bytes or fixed credential metadata.
for i in 0..<wire.len: wire[i] = 0
let selected = guaranteeAt(captured.value.owner, 1)
doAssert selected.error == GuaranteeError.None and uint32(selected.value.slot) == 2
var copy = selected.value
copy.credentials[1].validator = GuarantorIndex(0)
doAssert uint16(guaranteeAt(captured.value.owner, 1).value.credentials[1].validator) == 1
# A default owner is a failure, distinct from a validated empty sequence.
var absent: OwnedGuarantees
doAssert guaranteeAt(absent, 0).error == GuaranteeError.InvalidOwner
doAssert encodeOwnedGuarantees(absent, output).error == GuaranteeError.InvalidOwner
var badReport: OwnedReport
doAssert ownedReportOverlapsOutput(badReport, output).error == OwnershipError.InvalidOwner
doAssert not ownedReportOverlapsOutput(first.value, output).value
# A final invalid credential must be detected before any earlier source record writes its output.
values[1].credentials[1].validator = GuarantorIndex(1023)
for i in 0..<output.len: output[i] = 0xA5
let failed = encodeGuarantees(values.toOpenArray(0, 1), limits, output)
doAssert failed.error == GuaranteeError.InvalidValidator
for value in output: doAssert value == 0xA5 # Whole destination remains unchanged.
values[1].credentials[1].validator = GuarantorIndex(1)
# The backing array has enough real bytes for this alias fixture's full output extent.
doAssert encoded.value <= sizeof(values)
let alias = cast[ptr UncheckedArray[byte]](addr values[0])
doAssert encodeGuarantees(values.toOpenArray(0, 1), limits,
  alias.toOpenArray(0, encoded.value-1)).error == GuaranteeError.AliasedBuffers
# Optimized builds retain variant field guards even when a caller deliberately ignores an error.
var guarded = false
try:
  discard decodeGuarantees(@[255'u8], limits).value.count
except FieldDefect:
  # Reading nonexistent progress is rejected by Nim's checked tagged-result boundary.
  guarded = true
doAssert guarded
# Empty sequences capture a real owner and canonical one-byte count.
var empty: array[1, byte]
let decodedEmpty = decodeGuarantees(empty, limits)
doAssert decodedEmpty.error == GuaranteeError.None and decodedEmpty.value.count == 0

echo "Nim guarantees: retained ownership, late failures, aliases and guarded results passed"
