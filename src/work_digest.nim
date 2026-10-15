## Full work digest, pinned Gray Paper v0.7.1 C.2 and reporting equation workdigest.
import ./[natural, fixed_unsigned, bounded, composite]

type
  # Owned 32-byte code hash, nominally separate from a payload hash; no hashing is performed here.
  CodeHash* = distinct array[32, byte]
  # Owned 32-byte payload hash, whose bytes are serialized in their supplied order.
  PayloadHash* = distinct array[32, byte]
  # Gas units; accumulation gas uses E8 while refinement gas uses a canonical natural.
  Gas* = distinct uint64
  # Number of imported segments, serialized as a general natural.
  ImportCount* = distinct uint64
  # Number of extrinsics used by refinement, separate from their aggregate size.
  ExtrinsicCount* = distinct uint64
  # Aggregate extrinsic size in bytes, serialized as a general natural.
  ExtrinsicBytes* = distinct uint64
  # Number of exported segments, independent of import count.
  ExportCount* = distinct uint64
  RefineLoad* = object
    gasUsed*: Gas
    imports*: ImportCount
    extrinsicCount*: ExtrinsicCount
    extrinsicSize*: ExtrinsicBytes
    exports*: ExportCount
  # Owned fixed fields plus a work output whose successful span borrows the matching input/pool.
  WorkDigest* = object
    service*: ServiceIndex
    codeHash*: CodeHash
    payloadHash*: PayloadHash
    accumulateGas*: Gas
    output*: WorkOutput
    refine*: RefineLoad
  # Check error before reading value; failures have no consumed count or digest fields.
  DigestResult* = object
    case error*: CompositeError
    of CompositeError.None:
      # Only success carries decoded/committed data and its completed extent.
      value*: WorkDigest
      consumed*: int
    else:
      # Failure has no value, span, count or consumed/written metadata.
      discard

# Compare pointer differences without overflowing endpoint addition; empty spans never overlap.
proc digestAlias(a: pointer, alen: int, b: pointer, blen: int): bool {.raises: [].} =
  # Empty borrowed/written spans have no bytes in common.
  if alen == 0 or blen == 0: return false
  let left = cast[uint](a)
  let right = cast[uint](b)
  # Measure from whichever address occurs first.
  if left <= right: right - left < uint(alen)
  else: left - right < uint(blen) # Reverse the spans when the destination begins first.

# Gather metrics in normative order without treating their nominal public types as interchangeable.
proc metrics(load: RefineLoad): array[5, uint64] {.raises: [].} =
  [uint64(load.gasUsed), uint64(load.imports), uint64(load.extrinsicCount),
   uint64(load.extrinsicSize), uint64(load.exports)]

# Serialize the complete tuple into caller storage after validating every field, extent and borrowed pool.
proc encodeDigestBorrowed*(source: WorkDigest, pool: openArray[byte], limit: ByteLimit,
                   output: var openArray[byte]): CompositeWrite {.raises: [].} =
  # Own a value snapshot so output may overlap the original record without corrupting later fixed fields.
  var value = source
  let work = measureWork(value.output, pool.len, limit)
  # Invalid work variants/spans/policies cannot write the fixed prefix.
  if work.error != CompositeError.None: return work
  var suffix: array[5, EncodedNatural]
  var required = 76
  # The work extent must be representable before adding it to the fixed fields.
  if work.written > high(int) - required: return CompositeWrite(
      error: CompositeError.LengthOverflow)
  required += work.written
  # Encode each bounded-size metric locally and prove each subsequent extent before adding it.
  for i, metric in metrics(value.refine):
    suffix[i] = natural.encode(JamNatural(metric))
    if required > high(int) - suffix[i].len: return CompositeWrite(
        error: CompositeError.LengthOverflow) # Safe sum.
    required += suffix[i].len
  # Require the entire tuple, including its final metric, to fit before mutation.
  if output.len < required: return CompositeWrite(error: CompositeError.OutputTooSmall)
  # Success borrows the entire pool through the commit; error variants have no borrowed payload.
  if value.output.kind == WorkKind.Success and pool.len > 0 and
      digestAlias(unsafeAddr pool[0], pool.len, addr output[0], required):
    return CompositeWrite(error: CompositeError.AliasedBuffers)
  let service = encodeFixed(FixedUnsigned(uint64(uint32(value.service))), ByteWidth(4))
  let gas = encodeFixed(FixedUnsigned(uint64(value.accumulateGas)), ByteWidth(8))
  # Commit the nominal service ID in four-byte little-endian order.
  for i in 0..<4: output[i] = service.encoded.bytes[i]
  for i in 0..<32:
    output[4 + i] = array[32, byte](value.codeHash)[i]
    output[36 + i] = array[32, byte](value.payloadHash)[i]
  # Accumulation gas is fixed width rather than the variable refinement-gas format.
  for i in 0..<8: output[68 + i] = gas.encoded.bytes[i]
  discard encodeWorkBorrowed(value.output, pool, limit, output.toOpenArray(76, 76 + work.written - 1))
  var cursor = 76 + work.written
  for field in suffix:
    for i in 0..<field.len: output[cursor + i] = field.bytes[i] # Commit each measured field byte.
    cursor += field.len
  CompositeWrite(error: CompositeError.None, written: required)

# Decode one complete digest prefix; returned successful blob coordinates refer to the original input.
proc decodeDigestBorrowed*(input: openArray[byte], limit: ByteLimit): DigestResult {.raises: [].} =
  # The fixed prefix must exist before reading any service, hash or gas byte.
  if input.len < 76: return DigestResult(error: CompositeError.Truncated)
  let work = decodeWorkBorrowed(input.toOpenArray(76, input.len - 1), limit)
  # Reject incomplete/invalid work outputs before interpreting suffix metrics.
  if work.error != CompositeError.None: return DigestResult(error: work.error)
  var cursor = 76 + work.consumed
  var numbers: array[5, uint64]
  # Every metric must be canonical and complete; a failing final field returns no digest.
  for i in 0..<5:
    let parsed = natural.decode(input.toOpenArray(cursor, input.len - 1))
    if not parsed.ok:
      return DigestResult(error: if parsed.error ==
          natural.truncated: CompositeError.Truncated else: CompositeError.NonCanonical)
    numbers[i] = uint64(parsed.value)
    cursor += parsed.consumed
  var value: WorkDigest
  value.service = ServiceIndex(uint32(uint64(decodeFixed(input, ByteWidth(4)).value)))
  value.accumulateGas = Gas(uint64(decodeFixed(input.toOpenArray(68, 75), ByteWidth(8)).value))
  var code, payload: array[32, byte]
  # Copy fixed hashes into owned value storage; only the output blob remains borrowed.
  for i in 0..<32:
    code[i] = input[4 + i]
    payload[i] = input[36 + i]
  value.codeHash = CodeHash(code)
  value.payloadHash = PayloadHash(payload)
  value.output = work.value
  # Move successful spans from the work subframe to original-input coordinates.
  if value.output.kind == WorkKind.Success: value.output.blob.offset += 76
  value.refine = RefineLoad(gasUsed: Gas(numbers[0]), imports: ImportCount(numbers[1]),
      extrinsicCount: ExtrinsicCount(numbers[2]), extrinsicSize: ExtrinsicBytes(numbers[3]),
          exports: ExportCount(numbers[4]))
  DigestResult(error: CompositeError.None, value: value, consumed: cursor)
