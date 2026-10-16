## White-box project-owned private-wire aliases; external compilation probes enforce that storage remains inaccessible.
include ../../src/c2_records

# Private fixture inspection requires a completely validated owner.
proc checked[T](parsed: RecordResult[T]): T =
  doAssert parsed.error == RecordError.None
  parsed.value

let limits = OperandLimits(outputBytes: ByteLimit(16), authBytes: ByteLimit(16),
  totalBlobBytes: ByteLimit(32), maxBytes: ByteLimit(1024))
let source = AccumulationOperand(output: OperandOutput(kind: WorkKind.Success, payload: @[1'u8]),
    authTrace: @[2'u8])
var bytes: array[1024, byte]
let count = checked(encodeOperand(source, limits, bytes))
let owner = checked(decodeOperand(bytes.toOpenArray(0, count-1), limits)).owner
let wire = cast[ptr UncheckedArray[byte]](addr owner.data.wire[0])
doAssert encodeOwnedOperand(owner, limits, wire.toOpenArray(0, count-1)).error ==
    RecordError.AliasedBuffers
doAssert copyOperandOutput(owner, wire.toOpenArray(0, 0)).error == RecordError.AliasedBuffers
doAssert copyOperandTrace(owner, wire.toOpenArray(0, 0)).error == RecordError.AliasedBuffers
doAssert owner.data.wire[0] == 0
echo "Nim C.2 records: private snapshot aliases passed"
