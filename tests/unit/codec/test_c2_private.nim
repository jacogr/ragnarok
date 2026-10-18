# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## White-box project-owned private-wire aliases; external compilation probes enforce that storage remains inaccessible.
import std/[assertions, syncio]
include ../../../src/codec/c2_records

# Private fixture inspection requires a completely validated owner.
proc checked[T](parsed: RecordResult[T]): T =
  assert parsed.error == RecordError.None
  parsed.value

let limits = OperandLimits(outputBytes: ByteLimit(16), authBytes: ByteLimit(16),
  totalBlobBytes: ByteLimit(32), maxBytes: ByteLimit(1024))
let source = AccumulationOperand(output: successfulOperandOutput(@[1'u8]),
    authTrace: @[2'u8])
var bytes: array[1024, byte] = default(array[1024, byte])
let count = checked(encodeOperand(source, limits, bytes))
let owner = checked(decodeOperand(bytes.toOpenArray(0, count-1), limits)).owner
let data = owner.data
assert data != nil
data.wire.setLen(1024)
data.wire.setLen(count)
let wire = cast[ptr array[1024, byte]](addr data.wire[0])
assert encodeOwnedOperand(owner, limits, wire[].toOpenArray(0, count-1)).error ==
    RecordError.AliasedBuffers
assert copyOperandOutput(owner, wire[].toOpenArray(0, 0)).error == RecordError.AliasedBuffers
assert copyOperandTrace(owner, wire[].toOpenArray(0, 0)).error == RecordError.AliasedBuffers
assert data.wire[0] == 0
echo "Nim C.2 records: private snapshot aliases passed"
