## Focused C.2 lifetime, resource, alias and selected-alternative regressions.
import ../../src/[c2_records, bounded, composite, work_digest, work_report, assurances]

# Complete success is required before reading application fields, retained owners or progress.
proc checked[T](parsed: RecordResult[T]): T =
  doAssert parsed.error == RecordError.None
  parsed.value

let policy = OperandLimits(outputBytes: ByteLimit(1024), authBytes: ByteLimit(1024),
  totalBlobBytes: ByteLimit(1024), maxBytes: ByteLimit(4096))
var source = AccumulationOperand(gas: Gas(128), output: OperandOutput(kind: WorkKind.Success,
  payload: @[1'u8, 2, 3]), authTrace: @[4'u8, 5])
var bytes: array[4096, byte]
let count = checked(encodeOperand(source, policy, bytes))
var owner = checked(decodeOperand(bytes.toOpenArray(0, count-1), policy)).owner
let retained = owner
owner = OwnedOperand()
# The private owner must ignore mutation/release of both encoded input and all original logical source sequences.
for i in 0..<bytes.len: bytes[i] = 0
source.output.payload[0] = 255
source.authTrace = @[]
let info = checked(operandInfo(retained))
doAssert uint64(info.gas) == 128 and info.output.length == 3 and info.authBytes == 2
var copy: array[8, byte]
doAssert checked(copyOperandOutput(retained, copy)) == 3 and copy[0] == 1
copy[0] = 255
doAssert checked(copyOperandOutput(retained, copy)) == 3 and copy[0] == 1
doAssert checked(copyOperandTrace(retained, copy)) == 2 and copy[0] == 4
var strict = policy
strict.totalBlobBytes = ByteLimit(4)
# Re-emission cannot bypass a stricter new aggregate policy, and late trace failure cannot write an earlier hash.
for i in 0..<bytes.len: bytes[i] = 0xA5
doAssert encodeOwnedOperand(retained, strict, bytes).error == RecordError.LimitExceeded
strict = policy; strict.outputBytes = ByteLimit(2)
doAssert encodeOwnedOperand(retained, strict, bytes).error == RecordError.LimitExceeded
strict = policy; strict.authBytes = ByteLimit(1)
doAssert encodeOwnedOperand(retained, strict, bytes).error == RecordError.LimitExceeded
strict = policy; strict.maxBytes = ByteLimit(uint64(count-1))
doAssert encodeOwnedOperand(retained, strict, bytes).error == RecordError.LimitExceeded
strict = policy; strict.totalBlobBytes = ByteLimit(4)
source.authTrace = @[4'u8, 5]
doAssert encodeOperand(source, strict, bytes).error == RecordError.LimitExceeded
# Every failed byte in the complete caller destination remains unchanged.
for octet in bytes: doAssert octet == 0xA5
# Real owner-array storage provides a valid whole-record alias fixture without extending beyond its allocation.
var ownerBacking: array[128, OwnedOperand]
ownerBacking[0] = retained
let ownerBytes = cast[ptr UncheckedArray[byte]](addr ownerBacking[0])
doAssert sizeof(ownerBacking) >= count
doAssert encodeOwnedOperand(ownerBacking[0], policy, ownerBytes.toOpenArray(0, count-1)).error ==
    RecordError.AliasedBuffers
doAssert copyOperandOutput(ownerBacking[0], ownerBytes.toOpenArray(0, 2)).error ==
    RecordError.AliasedBuffers
doAssert copyOperandTrace(ownerBacking[0], ownerBytes.toOpenArray(0, 1)).error ==
    RecordError.AliasedBuffers
var missing: OwnedOperand
doAssert operandInfo(missing).error == RecordError.InvalidOwner
doAssert copyOperandOutput(missing, copy).error == RecordError.InvalidOwner
doAssert copyOperandTrace(missing, copy).error == RecordError.InvalidOwner
doAssert encodeOwnedOperand(missing, policy, bytes).error == RecordError.InvalidOwner
# Standalone availability copies fields and accepts tiny cardinality six while rejecting a wrong configured domain.
var availability = AvailabilitySpec(erasureShards: ErasureShards(6))
let config = AvailabilityConfig(cores: CoreCount(2), maxBytes: ByteLimit(104))
doAssert checked(encodeAvailability(availability, config, bytes)) == 104
let av = checked(decodeAvailability(bytes, config))
bytes[0] = 255
doAssert av.value.packageHash.bytes[0] == 0 and av.consumed == 104
let avBytes = cast[ptr UncheckedArray[byte]](addr availability)
doAssert sizeof(availability) >= 104
doAssert encodeAvailability(availability, config, avBytes.toOpenArray(0, 103)).error ==
    RecordError.AliasedBuffers
# Real source arrays provide enough allocated backing for complete descriptor-alias destinations.
var transfers: array[2, DeferredTransfer]
let transferBytes = cast[ptr UncheckedArray[byte]](addr transfers[0])
doAssert encodeTransfer(transfers[0], ByteLimit(153), transferBytes.toOpenArray(0, 152)).error ==
    RecordError.AliasedBuffers
var sources: array[4, AccumulationOperand]
sources[0] = source
let descriptorBytes = cast[ptr UncheckedArray[byte]](addr sources[0])
doAssert encodeOperand(sources[0], policy, descriptorBytes.toOpenArray(0, count-1)).error ==
    RecordError.AliasedBuffers
var unions: array[4, AccumulationSource]
unions[0] = AccumulationSource(kind: AccumulationKind.Operand, operand: source)
let unionBytes = cast[ptr UncheckedArray[byte]](addr unions[0])
doAssert encodeAccumulationInput(unions[0], policy, unionBytes.toOpenArray(0, count-1)).error ==
    RecordError.AliasedBuffers
# Reserve genuine backing capacity while restoring exact short source lengths; earlier output must protect later payload storage.
source.output.payload.setLen(1024)
source.output.payload.setLen(3)
let payloadBytes = cast[ptr UncheckedArray[byte]](addr source.output.payload[0])
doAssert encodeOperand(source, policy, payloadBytes.toOpenArray(0, count-1)).error ==
    RecordError.AliasedBuffers
source.authTrace.setLen(1024)
source.authTrace.setLen(2)
let traceBytes = cast[ptr UncheckedArray[byte]](addr source.authTrace[0])
doAssert encodeOperand(source, policy, traceBytes.toOpenArray(0, count-1)).error ==
    RecordError.AliasedBuffers
source.output = OperandOutput(kind: WorkKind.Panic)
let errorSize = checked(encodeOperand(source, policy, bytes))
let errorOwner = checked(decodeOperand(bytes.toOpenArray(0, errorSize-1), policy)).owner
var empty: seq[byte]
doAssert copyOperandOutput(errorOwner, empty).error == RecordError.NoPayload
var guarded = false
try:
  # Error output metadata cannot expose a default success payload length.
  discard checked(operandInfo(errorOwner)).output.length
except FieldDefect:
  # Checked optimized compilation must preserve the selected-output guard.
  guarded = true
doAssert guarded
guarded = false
try:
  # Rejected input cannot publish a default owner or consumed cursor.
  discard decodeOperand(@[2'u8], policy).value.consumed
except FieldDefect:
  # Failure alternatives remain inaccessible independently of successful work errors.
  guarded = true
doAssert guarded
guarded = false
try:
  # Uninitialized results cannot fabricate a retained owner or consumed cursor either.
  var absent: RecordResult[OperandRead]
  discard absent.value.consumed
except FieldDefect:
  # Defaults retain the same failure-only variant guard as explicit decoder rejection.
  guarded = true
doAssert guarded
doAssert checked(encodeTransfer(transfers[0], ByteLimit(153), bytes)) == 153
# Both selected source alternatives protect the complete containing union descriptor.
unions[0] = AccumulationSource(kind: AccumulationKind.Transfer, transfer: transfers[0])
doAssert encodeAccumulationInput(unions[0], policy, unionBytes.toOpenArray(0, 152)).error ==
    RecordError.AliasedBuffers
let unionTransfer = checked(decodeAccumulationInput(bytes, policy))
guarded = false
try:
  # A selected transfer cannot expose the inactive operand handle.
  discard unionTransfer.value.operand
except FieldDefect:
  # The accumulation union also preserves its selected-alternative guard.
  guarded = true
doAssert guarded
echo "Nim C.2 records: retained owners, fixed copies, strict policy, aliases and variant guards passed"
