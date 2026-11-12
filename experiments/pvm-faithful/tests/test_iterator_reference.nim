# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Differential malformed-stream iteration, PC boundaries and jump-target admission.

import std/[assertions, syncio]
import ../decode

proc word(data: string, at, length: int): uint64 =
  ## Read independently framed oracle fields only after proving their extents.
  assert at >= 0 and at <= data.len and length >= 0 and length <= data.len-at
  result = 0
  for index in 0..<length: result = result or (uint64(byte(data[at+index])) shl (8*index))

var data = ""
try:
  data = readFile("build/pvm-faithful/iterator.bin")
except:
  quit 2
assert data.len >= 12 and data[0..7] == "PVFITR02"
let count = int(word(data, 8, 4))
assert count == 320
var cursor = 12
for sample in 0..<count:
  # Copy only oracle inputs; candidate iteration cannot manufacture expected output rows.
  let length = int(word(data, cursor, 4))
  assert length < 128
  cursor += 4
  var code = newSeq[byte](length)
  var mask = newSeq[byte]((length+7) div 8)
  for index in 0..<code.len: code[index] = byte(data[cursor+index])
  cursor += code.len
  for index in 0..<mask.len: mask[index] = byte(data[cursor+index])
  cursor += mask.len
  for offset in 0..<length+2:
    assert byte(data[cursor]) <= 1
    assert validJump(code, mask, uint32(offset)) == (byte(data[cursor]) == 1), "faithful jump target mismatch"
    assert enclosingBlock(code, mask, uint32(offset)) == uint32(word(data, cursor+1, 4)), "faithful enclosing block mismatch"
    cursor += 5
  for invocation in 0..<14:
    # Compare the entire iterator, including injected invalid instructions and their next PCs.
    let offset = uint32(word(data, cursor, 4))
    let bounded = byte(data[cursor+4]) == 1
    let rows = int(word(data, cursor+5, 4))
    assert rows <= length+2
    cursor += 9
    var stream = initCursor(mask, length, offset, bounded)
    var parsed = default(ParsedInstruction)
    for row in 0..<rows:
      assert stream.next(code, mask, parsed), "faithful missing iterator row"
      assert parsed.offset == uint32(word(data, cursor, 4)), "faithful iterator PC mismatch"
      assert parsed.nextOffset == uint32(word(data, cursor+4, 4)), "faithful iterator next PC mismatch"
      assert uint32(ord(parsed.instruction.opcode)) == uint32(word(data, cursor+8, 4)), "faithful iterator opcode mismatch"
      let inst = parsed.instruction
      let actual = [uint64(inst.a), uint64(inst.b), uint64(inst.c), uint64(inst.x), uint64(inst.y), inst.wide]
      for field in 0..<actual.len:
        assert actual[field] == word(data, cursor+12+8*field, 8), "faithful iterator operand mismatch"
      cursor += 60
    assert not stream.next(code, mask, parsed), "faithful extra iterator row"
assert cursor == data.len
echo "faithful iterator and jump reference passed: ", count
