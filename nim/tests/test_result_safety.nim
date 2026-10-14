import ../src/[natural, fixed_unsigned, bounded, composite, work_digest]

# Deliberate caller misuse must raise the checked field error, never expose a default decoded value.
template unavailable(expression: untyped) =
  var rejected = false
  try:
    discard expression
  except FieldDefect:
    rejected = true # Reading the inactive success branch is a caller error, not a decoder failure.
  doAssert rejected

var unset: DigestResult
doAssert unset.error == CompositeError.Uninitialized
unavailable(unset.value)
# Empty input yields failure alternatives across the primitive and nested decoder families.
let naturalFailure = natural.decode([])
unavailable(naturalFailure.value)
let fixedFailure = decodeFixed([], ByteWidth(1))
unavailable(fixedFailure.consumed)
let blobFailure = decodeBytesBorrowed([], ByteLimit(1))
unavailable(blobFailure.offset)
unavailable(blobFailure.length)
unavailable(blobFailure.consumed)
var scalarOutput: array[1, FixedUnsigned]
let sequenceFailure = decodeSequence([], ByteWidth(1), ElementLimit(1), scalarOutput)
unavailable(sequenceFailure.count)
let optionalFailure = decodeOptionalBorrowed([], ByteLimit(1))
unavailable(optionalFailure.value)
let workFailure = decodeWorkBorrowed([], ByteLimit(1))
unavailable(workFailure.value)
var records: array[1, Preimage]
let limits = PreimageLimits(items: ElementLimit(1), perBlob: ByteLimit(1),
    totalBlobBytes: ByteLimit(1))
let preimageFailure = decodePreimagesBorrowed([], limits, records)
unavailable(preimageFailure.count)
let digestFailure = decodeDigestBorrowed([], ByteLimit(1))
unavailable(digestFailure.value)
unavailable(digestFailure.consumed)
var destination: array[1, byte]
let writeFailure = encodeBytes([1'u8], ByteLimit(0), destination)
unavailable(writeFailure.written)
let compositeFailure = encodeWorkBorrowed(WorkOutput(kind: WorkKind.Success, blob: BlobSpan(
    offset: 2, length: 1)), [], ByteLimit(1), destination)
unavailable(compositeFailure.written)
# Zero is a legitimate decoded value or count; only the variant discriminator denotes failure.
let zero = natural.decode([0'u8])
doAssert zero.ok and uint64(zero.value) == 0
let empty = decodePreimagesBorrowed([0'u8], limits, records)
doAssert empty.error == CompositeError.None and empty.count == 0 and empty.consumed == 1
let zeroWidth = decodeFixed([], ByteWidth(0))
doAssert zeroWidth.ok and zeroWidth.consumed == 0
# An error is a decoded *work-output value*, distinct from a failure to decode the schema.
let workError = decodeWorkBorrowed([1'u8], ByteLimit(0))
doAssert workError.error == CompositeError.None and workError.value.kind == WorkKind.OutOfGas
echo "Nim result safety: failed payload/metadata inaccessible; valid zero and work-error values preserved"
