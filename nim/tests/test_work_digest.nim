import ../src/[work_digest, composite, bounded]

# Arbitrary-input entry point checks successful metadata and exact full-prefix reconstruction without allocation.
proc fuzzDigest*(input: openArray[byte]) =
  let parsed = decodeDigestBorrowed(input, ByteLimit(64))
  # Failed tuples must not advance a caller cursor, including a malformed final metric.
  if parsed.error != CompositeError.None:
    doAssert parsed.error != typeof(parsed.error).None
    return
  var bytes: array[256, byte]
  let written = encodeDigestBorrowed(parsed.value, input, ByteLimit(64), bytes)
  doAssert written.error == CompositeError.None and written.written == parsed.consumed
  # Include owned fixed fields, original-input-relative blob bytes and all five suffix metrics.
  for i in 0..<written.written: doAssert bytes[i] == input[i]

var code, payload: array[32, byte]
# Distinct patterned hashes catch swapped fields or reversed byte order.
for i in 0..<32:
  code[i] = byte(i)
  payload[i] = byte(255 - i)
var pool = [1'u8, 2, 3]
var value = WorkDigest(service: ServiceIndex(high(uint32)), codeHash: CodeHash(code),
    payloadHash: PayloadHash(payload), accumulateGas: Gas(high(uint64)),
    output: WorkOutput(kind: WorkKind.Success, blob: BlobSpan(offset: 0, length: 3)),
    refine: RefineLoad(gasUsed: Gas(127), imports: ImportCount(128), extrinsicCount: ExtrinsicCount(
        16384), extrinsicSize: ExtrinsicBytes(1'u64 shl 56), exports: ExportCount(high(uint64))))
var wire: array[256, byte]
let encoded = encodeDigestBorrowed(value, pool, ByteLimit(3), wire)
doAssert encoded.error == CompositeError.None
let decoded = decodeDigestBorrowed(wire.toOpenArray(0, encoded.written - 1), ByteLimit(3))
doAssert decoded.error == CompositeError.None and decoded.consumed == encoded.written
doAssert decoded.value.output.blob.offset == 78 and decoded.value.output.blob.length == 3
doAssert uint64(decoded.value.refine.imports) == 128 and uint64(decoded.value.refine.exports) ==
    high(uint64)
fuzzDigest(wire.toOpenArray(0, encoded.written - 1))
# Every incomplete tuple prefix, including every suffix byte, must fail atomically.
for cut in 0..<encoded.written:
  let short = decodeDigestBorrowed(wire.toOpenArray(0, cut - 1), ByteLimit(3))
  doAssert short.error == CompositeError.Truncated
# A short final suffix destination must preserve the fixed prefix as well as the rest of storage.
for b in wire.mitems: b = 77
let shortWrite = encodeDigestBorrowed(value, pool, ByteLimit(3), wire.toOpenArray(0,
    encoded.written - 2))
doAssert shortWrite.error == CompositeError.OutputTooSmall
# Verify the whole sentinel buffer after the failed write.
for b in wire: doAssert b == 77
# A present empty blob still borrows its pool; later metric writes must not overwrite any pool bytes.
value.output = WorkOutput(kind: WorkKind.Success, blob: BlobSpan(offset: 0, length: 0))
let before = wire
doAssert encodeDigestBorrowed(value, wire, ByteLimit(0), wire).error ==
    CompositeError.AliasedBuffers
doAssert wire == before
# Invalid nested spans fail before even a nominal fixed field is committed.
value.output = WorkOutput(kind: WorkKind.Success, blob: BlobSpan(offset: high(int), length: 1))
doAssert encodeDigestBorrowed(value, pool, ByteLimit(3), wire).error == CompositeError.InvalidSpan
doAssert wire == before
var state = 0x444947455354'u64
# Valid fixed-prefix bytes make fuzzing reach the variant and five metrics rather than only the short-prefix guard.
for iteration in 0..<10000:
  var input: array[160, byte]
  # Deterministic xorshift supplies arbitrary bytes without a cryptographic dependency.
  for b in input.mitems:
    state = state xor (state shl 13)
    state = state xor (state shr 7)
    state = state xor (state shl 17)
    b = byte(state and 255)
  fuzzDigest(input.toOpenArray(0, iteration mod 161 - 1))
echo "Nim work digest: full tuple, boundaries, atomic failures and 10000 fuzz cases passed"
