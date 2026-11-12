# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Differential blob admission and every retained section payload, including malformed inputs.

import std/[assertions, syncio]
import ../program

proc word(data: string, at, length: int): uint64 =
  ## Oracle framing remains distinct from candidate blob varint/section parsing.
  assert at >= 0 and at <= data.len and length >= 0 and length <= data.len-at
  result = 0
  for index in 0..<length: result = result or (uint64(byte(data[at+index])) shl (8*index))

var data = ""
try:
  data = readFile("build/pvm-faithful/program.bin")
except:
  quit 2
assert data.len >= 12 and data[0..7] == "PVFBLB01"
let count = int(word(data, 8, 4))
assert count > 1000 and count < 10000
var cursor = 12
var accepted = 0
for row in 0..<count:
  # Each input is admitted independently; no upstream object crosses into the candidate.
  let length = int(word(data, cursor, 4))
  cursor += 4
  assert length <= data.len-cursor
  var input = newSeq[byte](length)
  for index in 0..<length: input[index] = byte(data[cursor+index])
  cursor += length
  let expected = byte(data[cursor])
  cursor += 1
  assert expected <= 2
  let source = sharedBytes(input)
  let answer = parse(source)
  if expected == 2:
    assert not answer.ok and answer.error == BlobError.UnsupportedIsa, "faithful ISA subset mismatch"
  elif expected == 0:
    assert not answer.ok, "faithful blob accepted invalid input"
  else:
    if not answer.ok: echo "blob mismatch row=", row, " bytes=", length, " reason=", ord(answer.error)
    assert answer.ok, "faithful blob rejected valid input"
    accepted += 1
    let blob = answer.blob()
    let sizes = [blob.parts.roSize, blob.parts.rwSize, blob.parts.stackSize]
    for size in sizes:
      assert size == uint32(word(data, cursor, 4)), "faithful blob geometry mismatch"
      cursor += 4
    let sections = [blob.parts.ro, blob.parts.rw, blob.parts.encodedCode, blob.parts.importOffsets,
      blob.parts.importSymbols, blob.parts.exports, blob.parts.debugStrings,
      blob.parts.debugPrograms,
      blob.parts.debugRanges, blob.parts.metadata, blob.code, blob.mask]
    for section in sections:
      let expectedLength = int(word(data, cursor, 4))
      cursor += 4
      assert section.len == expectedLength, "faithful blob section length mismatch"
      assert expectedLength <= data.len-cursor
      let actual = section.view()
      for index in 0..<actual.len:
        assert actual[index] == byte(data[cursor+index]), "faithful blob section bytes mismatch"
      cursor += expectedLength
    let jumps = int(word(data, cursor, 4))
    cursor += 4
    let actualJumps = if blob.jumpWidth == 0: 0 else: blob.jumpTable.len div int(blob.jumpWidth)
    assert jumps == actualJumps, "faithful jump table length mismatch"
    let raw = blob.jumpTable.view()
    for index in 0..<jumps:
      var target = 0'u32
      for offset in 0..<int(blob.jumpWidth):
        target = target or (uint32(raw[index*int(blob.jumpWidth)+offset]) shl (8*offset))
      assert target == uint32(word(data, cursor, 4)), "faithful jump table target mismatch"
      cursor += 4
assert cursor == data.len
echo "faithful blob reference passed: ", count, ", accepted: ", accepted
