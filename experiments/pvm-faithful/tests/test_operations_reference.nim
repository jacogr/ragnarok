# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Cross all signed/unsigned arithmetic helpers against the pinned Rust implementation.

import std/[assertions, syncio]
import ../operations

proc word(data: string, at: int): uint64 =
  ## Read one bounded oracle word without invoking any candidate arithmetic helper.
  assert at >= 0 and at <= data.len-8
  result = 0
  for index in 0..<8: result = result or (uint64(byte(data[at+index])) shl (8*index))

var data = ""
try:
  data = readFile("build/pvm-faithful/operations.bin")
except:
  quit 2
assert data.len >= 12 and data[0..7] == "PVFOPS01"
var count = 0'u32
for index in 0..<4: count = count or (uint32(byte(data[8+index])) shl (8*index))
assert count == 4217 and data.len == 12+int(count)*128
var cursor = 12
for row in 0..<int(count):
  # Explicit casts preserve two's-complement operand/result bits across signed domains.
  let a = word(data, cursor)
  let b = word(data, cursor+8)
  let a32 = uint32(a)
  let b32 = uint32(b)
  let ai = cast[int64](a)
  let bi = cast[int64](b)
  let ai32 = cast[int32](a32)
  let bi32 = cast[int32](b32)
  let actual = [uint64(divu(a32, b32)), divu64(a, b), uint64(remu(a32, b32)), remu64(a, b),
    uint64(cast[uint32](divs(ai32, bi32))), cast[uint64](divs64(ai, bi)),
    uint64(cast[uint32](rems(ai32, bi32))), cast[uint64](rems64(ai, bi)),
    uint64(cast[uint32](mulh(ai32, bi32))), cast[uint64](mulh64(ai, bi)),
    uint64(cast[uint32](mulhsu(ai32, b32))), cast[uint64](mulhsu64(ai, b)),
    uint64(mulhu(a32, b32)), mulhu64(a, b)]
  for operation in 0..<actual.len:
    assert actual[operation] == word(data, cursor+16+operation*8), "faithful arithmetic mismatch"
  cursor += 128
assert cursor == data.len
echo "faithful arithmetic reference passed: ", count
