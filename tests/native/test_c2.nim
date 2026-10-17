## Focused C.2 lifetime, resource, alias and selected-alternative regressions.
import std/[assertions, syncio]
import ../../src/codec/[c2_records, bounded, composite, work_digest, work_report, assurances]

# Complete success is required before reading application fields, retained owners or progress.
proc checked[T](parsed: RecordResult[T]): T =
  assert parsed.error == RecordError.None
  parsed.value

let policy = OperandLimits(outputBytes: ByteLimit(1024), authBytes: ByteLimit(1024),
  totalBlobBytes: ByteLimit(1024), maxBytes: ByteLimit(4096))
var source = AccumulationOperand(gas: Gas(128), output: successfulOperandOutput(@[1'u8, 2, 3]),
    authTrace: @[4'u8, 5])
var bytes: array[4096, byte] = default(array[4096, byte])
let count = checked(encodeOperand(source, policy, bytes))
var owner = checked(decodeOperand(bytes.toOpenArray(0, count-1), policy)).owner
let retained = owner
owner = OwnedOperand()
# The private owner must ignore mutation/release of both encoded input and all original logical source sequences.
for i in 0..<bytes.len: bytes[i] = 0
editOperandPayload(source.output)[0] = 255
source.authTrace = @[]
let info = checked(operandInfo(retained))
assert uint64(info.gas) == 128 and info.output.length == 3 and info.authBytes == 2
var copy: array[8, byte] = default(array[8, byte])
assert checked(copyOperandOutput(retained, copy)) == 3 and copy[0] == 1
copy[0] = 255
assert checked(copyOperandOutput(retained, copy)) == 3 and copy[0] == 1
assert checked(copyOperandTrace(retained, copy)) == 2 and copy[0] == 4
var strict = policy
strict.totalBlobBytes = ByteLimit(4)
# Re-emission cannot bypass a stricter new aggregate policy, and late trace failure cannot write an earlier hash.
for i in 0..<bytes.len: bytes[i] = 0xA5
assert encodeOwnedOperand(retained, strict, bytes).error == RecordError.LimitExceeded
strict = policy; strict.outputBytes = ByteLimit(2)
assert encodeOwnedOperand(retained, strict, bytes).error == RecordError.LimitExceeded
strict = policy; strict.authBytes = ByteLimit(1)
assert encodeOwnedOperand(retained, strict, bytes).error == RecordError.LimitExceeded
strict = policy; strict.maxBytes = ByteLimit(uint64(count-1))
assert encodeOwnedOperand(retained, strict, bytes).error == RecordError.LimitExceeded
strict = policy; strict.totalBlobBytes = ByteLimit(4)
source.authTrace = @[4'u8, 5]
assert encodeOperand(source, strict, bytes).error == RecordError.LimitExceeded
# Every failed byte in the complete caller destination remains unchanged.
for octet in bytes: assert octet == 0xA5
# Real owner-array storage provides a valid whole-record alias fixture without extending beyond its allocation.
var ownerBacking: array[128, OwnedOperand] = default(array[128, OwnedOperand])
ownerBacking[0] = retained
let ownerBytes = cast[ptr array[sizeof(ownerBacking), byte]](addr ownerBacking[0])
assert sizeof(ownerBacking) >= count
assert encodeOwnedOperand(ownerBacking[0], policy, ownerBytes[].toOpenArray(0, count-1)).error ==
    RecordError.AliasedBuffers
assert copyOperandOutput(ownerBacking[0], ownerBytes[].toOpenArray(0, 2)).error ==
    RecordError.AliasedBuffers
assert copyOperandTrace(ownerBacking[0], ownerBytes[].toOpenArray(0, 1)).error ==
    RecordError.AliasedBuffers
var missing: OwnedOperand = default(OwnedOperand)
assert operandInfo(missing).error == RecordError.InvalidOwner
assert copyOperandOutput(missing, copy).error == RecordError.InvalidOwner
assert copyOperandTrace(missing, copy).error == RecordError.InvalidOwner
assert encodeOwnedOperand(missing, policy, bytes).error == RecordError.InvalidOwner
# Standalone availability copies fields and accepts tiny cardinality six while rejecting a wrong configured domain.
var availability = AvailabilitySpec(erasureShards: ErasureShards(6))
let config = AvailabilityConfig(cores: CoreCount(2), maxBytes: ByteLimit(104))
assert checked(encodeAvailability(availability, config, bytes)) == 104
let av = checked(decodeAvailability(bytes, config))
bytes[0] = 255
assert av.value.packageHash.bytes[0] == 0 and av.consumed == 104
let avBytes = cast[ptr array[sizeof(availability), byte]](addr availability)
assert sizeof(availability) >= 104
assert encodeAvailability(availability, config, avBytes[].toOpenArray(0, 103)).error ==
    RecordError.AliasedBuffers
# Real source arrays provide enough allocated backing for complete descriptor-alias destinations.
var transfers: array[2, DeferredTransfer] = default(array[2, DeferredTransfer])
let transferBytes = cast[ptr array[sizeof(transfers), byte]](addr transfers[0])
assert encodeTransfer(transfers[0], ByteLimit(153), transferBytes[].toOpenArray(0, 152)).error ==
    RecordError.AliasedBuffers
var sources: array[4, AccumulationOperand] = default(array[4, AccumulationOperand])
sources[0] = source
let descriptorBytes = cast[ptr array[sizeof(sources), byte]](addr sources[0])
assert encodeOperand(sources[0], policy, descriptorBytes[].toOpenArray(0, count-1)).error ==
    RecordError.AliasedBuffers
var unions: array[4, AccumulationSource] = default(array[4, AccumulationSource])
unions[0] = operandSource(source)
let unionBytes = cast[ptr array[sizeof(unions), byte]](addr unions[0])
assert encodeAccumulationInput(unions[0], policy, unionBytes[].toOpenArray(0, count-1)).error ==
    RecordError.AliasedBuffers
# Reserve genuine backing capacity while restoring exact short source lengths; earlier output must protect later payload storage.
editOperandPayload(source.output).setLen(1024)
editOperandPayload(source.output).setLen(3)
let payloadBytes = cast[ptr array[1024, byte]](addr editOperandPayload(source.output)[0])
assert encodeOperand(source, policy, payloadBytes[].toOpenArray(0, count-1)).error ==
    RecordError.AliasedBuffers
source.authTrace.setLen(1024)
source.authTrace.setLen(2)
let traceBytes = cast[ptr array[1024, byte]](addr source.authTrace[0])
assert encodeOperand(source, policy, traceBytes[].toOpenArray(0, count-1)).error ==
    RecordError.AliasedBuffers
source.output = failedOperandOutput(WorkKind.Panic)
let errorSize = checked(encodeOperand(source, policy, bytes))
let errorOwner = checked(decodeOperand(bytes.toOpenArray(0, errorSize-1), policy)).owner
var empty: seq[byte] = default(seq[byte])
assert copyOperandOutput(errorOwner, empty).error == RecordError.NoPayload
assert checked(encodeTransfer(transfers[0], ByteLimit(153), bytes)) == 153
# Both selected source alternatives protect the complete containing union descriptor.
unions[0] = transferSource(transfers[0])
assert encodeAccumulationInput(unions[0], policy, unionBytes[].toOpenArray(0, 152)).error ==
    RecordError.AliasedBuffers
let unionTransfer = checked(decodeAccumulationInput(bytes, policy))
# A copied source branch and copied source payload must not mutate the original union descriptor.
let sourceUnion = operandSource(AccumulationOperand(output: successfulOperandOutput(@[1'u8, 2]),
    authTrace: @[3'u8]))
var sourceCopy = sourceUnion.operand
editOperandPayload(sourceCopy.output)[0] = 99
assert operandPayloadCopies(sourceUnion.operand.output)[0] == 1
var payloadCopy = operandPayloadCopies(sourceUnion.operand.output)
payloadCopy[0] = 88
assert operandPayloadCopies(sourceUnion.operand.output)[0] == 1

# Returning a local decoded union retains the operand after its source and outer result leave scope.
proc escapedOperand(): OwnedOperand =
  var source = AccumulationOperand(output: successfulOperandOutput(@[1'u8, 2, 3]), authTrace: @[4'u8, 5])
  var wire = newSeq[byte](256)
  let count = checked(encodeAccumulationInput(operandSource(source), policy, wire))
  result = checked(decodeAccumulationInput(wire.toOpenArray(0, count-1), policy)).value.operand
  # No retained coordinate may refer to either of these caller buffers.
  for i in 0..<wire.len: wire[i] = 0
  editOperandPayload(source.output)[0] = 99

# Each isolated scope replaces owners, mutates copied metadata/output and exercises every work-error alternative.
proc releaseCycle() =
  var current = escapedOperand()
  let original = current
  var replacement = AccumulationOperand(output: successfulOperandOutput(@[8'u8, 9, 10]),
      authTrace: @[6'u8, 7])
  var wire = newSeq[byte](256)
  let size = checked(encodeOperand(replacement, policy, wire))
  current = checked(decodeOperand(wire.toOpenArray(0, size-1), policy)).owner
  var bytes = newSeq[byte](8)
  assert checked(copyOperandOutput(current, bytes)) == 3 and bytes[0] == 8
  current = default(OwnedOperand)
  for i in 0..<wire.len: wire[i] = 0 # Replacing source and owner cannot rebind the retained original.
  var info = checked(operandInfo(original))
  info.packageHash.bytes[0] = 255
  assert checked(operandInfo(original)).packageHash.bytes[0] == 0
  assert checked(copyOperandOutput(original, bytes)) == 3 and bytes[0] == 1
  bytes[0] = 99
  assert checked(copyOperandOutput(original, bytes)) == 3 and bytes[0] == 1
  assert checked(copyOperandTrace(original, bytes)) == 2 and bytes[0] == 4
  # Error results remain valid complete operands with a final trace but no output payload.
  for kind in [WorkKind.OutOfGas, WorkKind.Panic, WorkKind.BadExports, WorkKind.Oversize,
      WorkKind.Bad, WorkKind.Big]:
    replacement.output = failedOperandOutput(kind)
    let size = checked(encodeOperand(replacement, policy, wire))
    let error = checked(decodeOperand(wire.toOpenArray(0, size-1), policy)).owner
    assert checked(operandInfo(error)).output.kind == kind
    assert copyOperandOutput(error, bytes).error == RecordError.NoPayload
    assert checked(copyOperandTrace(error, bytes)) == 2

# Warm public allocation paths before observing scoped ARC release with outer fixtures retained.
for i in 0..<100: releaseCycle()
let beforeRelease = getOccupiedMem()
# Every original/replaced/errored snapshot and copied source must release at the final scope boundary.
for i in 0..<1000: releaseCycle()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
echo "C2_ARC_RELEASE cycles=1000 occupied_before=", beforeRelease, " occupied_after=", afterRelease
echo "Nimony C.2: retained owners, fixed copies, strict policy, source independence and aliases passed"
