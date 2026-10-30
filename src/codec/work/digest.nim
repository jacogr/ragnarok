# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Full work digest, pinned Gray Paper v0.8.0 C.2 and reporting equation workdigest.
##
## Exposes nominal digest fields, WorkDigest and borrowed
## encodeDigestBorrowed/decodeDigestBorrowed results.

import ../[natural, fixed_unsigned, bounded, composite]

type
  CodeHash* = distinct array[32, byte] ## Owned 32-byte code hash, nominally separate from a payload hash; no hashing is performed here.
  PayloadHash* = distinct array[32, byte] ## Owned 32-byte payload hash, whose bytes are serialized in their supplied order.
  Gas* = distinct uint64 ## Gas units; a work digest uses E8 for accumulation gas and a natural for refinement gas.
                         ## The same units in a C.2 accumulation operand use a general natural rather than E8.
  ImportCount* = distinct uint64 ## Number of imported segments, serialized as a general natural.
  ExtrinsicCount* = distinct uint64 ## Number of extrinsics used by refinement, separate from their aggregate size.
  ExtrinsicBytes* = distinct uint64 ## Aggregate extrinsic size in bytes, serialized as a general natural.
  ExportCount* = distinct uint64 ## Number of exported segments, independent of import count.
  RefineLoad* = object
    gasUsed*: Gas
    imports*: ImportCount
    extrinsicCount*: ExtrinsicCount
    extrinsicSize*: ExtrinsicBytes
    exports*: ExportCount
  WorkDigest* = object ## Owned fixed fields plus a work output whose successful span borrows the matching input/pool.
    service*: ServiceIndex
    codeHash*: CodeHash
    payloadHash*: PayloadHash
    accumulateGas*: Gas
    output*: WorkOutput
    refine*: RefineLoad
  DigestResult* = object ## Private tagged state exposes complete copied digests only through guarded accessors.
    case status: CompositeError
    of None:
      # Successful spans remain relative to the original borrowed input.
      decodedValue: WorkDigest
      byteConsumed: int
    else:
      # Default/failure alternatives expose only a typed reason.
      discard

func error*(value: DigestResult): CompositeError =
  ## Read the reason without permitting callers to retag a failure as success.
  value.status

func value*(value: DigestResult): WorkDigest {.inline, requires: value.status ==
    CompositeError.None.} =
  ## A failed digest cannot expose default hashes, service identity or nested work output.
  value.decodedValue

func consumed*(value: DigestResult): int {.inline, requires: value.status == CompositeError.None.} =
  ## Only a complete digest prefix can advance the caller's cursor.
  value.byteConsumed

proc digestAlias(a: pointer, alen: int, b: pointer, blen: int): bool {.raises: [].} =
  ## Compare pointer differences without overflowing endpoint addition; empty spans never overlap.
  # Empty borrowed/written spans have no bytes in common.
  if alen == 0 or blen == 0: return false
  let left = cast[uint](a)
  let right = cast[uint](b)
  # Measure from whichever address occurs first.
  if left <= right: right - left < uint(alen)
  else: left - right < uint(blen) # Reverse the spans when the destination begins first.

proc metrics(load: RefineLoad): array[5, uint64] {.raises: [].} =
  ## Gather metrics in normative order without treating their nominal public types as interchangeable.
  [uint64(load.gasUsed), uint64(load.imports), uint64(load.extrinsicCount),
   uint64(load.extrinsicSize), uint64(load.exports)]

proc encodeDigestBorrowed*(source: WorkDigest, pool: openArray[byte], limit: ByteLimit,
                   output: var openArray[byte]): CompositeWrite {.raises: [].} =
  ## Serialize the complete tuple into caller storage after validating every field, extent and borrowed pool.
  # Own a value snapshot so output may overlap the original record without corrupting later fixed fields.
  var value = source
  let work = measureWork(value.output, pool.len, limit)
  # Invalid work variants/spans/policies cannot write the fixed prefix.
  if work.error != CompositeError.None: return work
  var suffix: array[5, EncodedNatural] = default(array[5, EncodedNatural])
  var required = 76
  # The work extent must be representable before adding it to the fixed fields.
  if work.written > high(int) - required: return compositeFailure(CompositeError.LengthOverflow)
  required += work.written
  # Encode each bounded-size metric locally and prove each subsequent extent before adding it.
  for i, metric in metrics(value.refine):
    suffix[i] = natural.encode(JamNatural(metric))
    if required > high(int) - suffix[i].len: return compositeFailure(CompositeError.LengthOverflow) # Safe sum.
    required += suffix[i].len
  # Require the entire tuple, including its final metric, to fit before mutation.
  if output.len < required: return compositeFailure(CompositeError.OutputTooSmall)
  # Success borrows the entire pool through the commit; error variants have no borrowed payload.
  if value.output.kind == WorkKind.Success and pool.len > 0 and
      digestAlias(unsafeAddr pool[0], pool.len, addr output[0], required):
    return compositeFailure(CompositeError.AliasedBuffers)
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
  compositeWritten(required)

proc decodeDigestBorrowed*(input: openArray[byte], limit: ByteLimit): DigestResult {.raises: [].} =
  ## Decode one complete digest prefix; returned successful blob coordinates refer to the original input.
  # The fixed prefix must exist before reading any service, hash or gas byte.
  if input.len < 76: return DigestResult(status: CompositeError.Truncated)
  let work = decodeWorkBorrowed(input.toOpenArray(76, input.len - 1), limit)
  # Reject incomplete/invalid work outputs before interpreting suffix metrics.
  if work.error != CompositeError.None: return DigestResult(status: work.error)
  var cursor = 76 + work.consumed
  var numbers: array[5, uint64] = default(array[5, uint64])
  # Every metric must be canonical and complete; a failing final field returns no digest.
  for i in 0..<5:
    let parsed = natural.decode(input.toOpenArray(cursor, input.len - 1))
    if not parsed.ok:
      return DigestResult(status: if parsed.error ==
          natural.truncated: CompositeError.Truncated else: CompositeError.NonCanonical)
    numbers[i] = uint64(parsed.value)
    cursor += parsed.consumed
  var value: WorkDigest = default(WorkDigest)
  value.service = ServiceIndex(uint32(uint64(decodeFixed(input, ByteWidth(4)).value)))
  value.accumulateGas = Gas(uint64(decodeFixed(input.toOpenArray(68, 75), ByteWidth(8)).value))
  var code: array[32, byte] = default(array[32, byte])
  var payload: array[32, byte] = default(array[32, byte])
  # Copy fixed hashes into owned value storage; only the output blob remains borrowed.
  for i in 0..<32:
    code[i] = input[4 + i]
    payload[i] = input[36 + i]
  value.codeHash = CodeHash(code)
  value.payloadHash = PayloadHash(payload)
  value.output = work.value
  # Move successful spans from the work subframe to original-input coordinates.
  if value.output.kind == WorkKind.Success:
    # The span accessor returns a copy; rebuild the variant with the proved original-input offset.
    let span = value.output.blob
    value.output = successfulWork(BlobSpan(offset: span.offset + 76, length: span.length))
  value.refine = RefineLoad(gasUsed: Gas(numbers[0]), imports: ImportCount(numbers[1]),
      extrinsicCount: ExtrinsicCount(numbers[2]), extrinsicSize: ExtrinsicBytes(numbers[3]),
          exports: ExportCount(numbers[4]))
  DigestResult(status: CompositeError.None, decodedValue: value, byteConsumed: cursor)
