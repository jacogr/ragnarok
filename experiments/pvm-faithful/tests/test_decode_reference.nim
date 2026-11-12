# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compare every raw opcode and operand length with the independent pinned public decoder.

import std/[assertions, syncio, envvars]
import ../decode

proc word(data: string, at, length: int): uint64 =
  ## Bounded little-endian wire decoding is separate from the candidate instruction decoder.
  assert at >= 0 and length >= 0 and at <= data.len and length <= data.len-at
  result = 0
  for index in 0..<length: result = result or (uint64(byte(data[at+index])) shl (8*index))

var data = ""
try:
  # The reference executable alone produces expectations; absence cannot become a passing test.
  data = readFile("build/pvm-faithful/decode.bin")
except:
  quit 2
assert data.len >= 12 and data[0..7] == "PVFDEC01"
let count = int(word(data, 8, 4))
assert count == 256*25*32 and data.len == 12+count*73
let corrupt = getEnv("RAGNAROK_FAITHFUL_CORRUPT") == "1"
var cursor = 12
for row in 0..<count:
  # Retain all 128 input bits even when the encoded instruction length is shorter.
  let value = [word(data, cursor, 8), word(data, cursor+8, 8)]
  let offset = uint32(word(data, cursor+16, 4))
  let length = uint32(byte(data[cursor+20]))
  let expectedOpcode = uint32(word(data, cursor+21, 4))
  let parsed = decode(value, offset, length)
  assert uint32(ord(parsed.opcode)) == expectedOpcode, "faithful opcode mismatch"
  let actual = [uint64(parsed.a), uint64(parsed.b), uint64(parsed.c),
    uint64(parsed.x), uint64(parsed.y), parsed.wide]
  for field in 0..<actual.len:
    let expected = word(data, cursor+25+8*field, 8) xor (if corrupt and row == 0 and field ==
        0: 1'u64 else: 0'u64)
    assert actual[field] == expected, "faithful decoder field mismatch"
  cursor += 73
assert cursor == data.len
echo "faithful raw decoder reference passed: ", count
