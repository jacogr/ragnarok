# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## All thirteen operand shapes retain independent frozen values and immutable source ownership.

import std/assertions
import std/syncio
import std/envvars
import ../../../src/pvm/program as pvm_program

proc number(data: string, at, width: int): uint64 =
  ## Read bounded independent fixed fields; this does not reuse the production operand decoder.
  assert at >= 0 and width in 1..8 and at <= data.len and width <= data.len - at
  result = 0
  for i in 0..<width:
    # Every field is little endian and contributes within a validated at-most-u64 extent.
    result = result or (uint64(byte(data[at + i])) shl (i * 8))

var data = ""
try:
  # Replay frozen data without an upstream dependency or runtime regeneration.
  data = readFile(getEnv("RAGNAROK_PVM_OPERAND"))
except:
  quit 2
assert data.len >= 12 and data[0..7] == "PVMOPR01" and number(data, 8, 4) == 62550
var cursor = 12
for row in 0..<62550:
  # Prove the entire header and body extent before narrowing or constructing either owner.
  assert cursor <= data.len and data.len - cursor >= 40
  let size = number(data, cursor, 4)
  let pc = number(data, cursor + 4, 4)
  assert size <= uint64(data.len - cursor - 40) and size <= 128 and pc in [0'u64, 3]
  let opcode = byte(data[cursor + 8])
  let skip = byte(data[cursor + 9])
  let shape = byte(data[cursor + 10])
  assert validOpcode(opcode) and skip <= 24 and shape <= 12
  assert byte(data[cursor + 15]) <= 8
  var wire = newSeq[byte](int(size))
  for i in 0..<wire.len:
    # Each profile captures its own copy of the exact original raw guest blob.
    wire[i] = byte(data[cursor + 40 + i])
  let paper = decodeProgram(wire, CodeAddress(pc), ProgramByteLimit(128), JumpCountLimit(0))
  let jam = decodeJamProgram(wire, CodeAddress(pc), ProgramByteLimit(128), JumpCountLimit(0))
  assert paper.error == ProgramError.None and jam.error == ProgramError.None
  let owners = [paper.value, jam.value]
  for i in 0..<wire.len:
    # Mutating the caller's input cannot change retained bytes or the owner's decode profile.
    wire[i] = 0
  for profile in 0..<2:
    # Compare every exposed field, including unused zeros and the explicit raw/JAM D difference.
    let decoded = instruction(owners[profile], CodeAddress(pc))
    assert decoded.error == ProgramError.None
    let item = decoded.value
    assert uint64(item.address) == pc and item.opcode == opcode and byte(item.skip) == skip
    assert byte(item.shape) == shape
    assert byte(item.a) == byte(data[cursor + 11]) and byte(item.b) == byte(data[cursor + 12])
    assert byte(item.d) == byte(data[cursor + 13 + profile])
    assert uint64(item.x) == number(data, cursor + 16, 8)
    assert uint64(item.y) == number(data, cursor + 24, 8)
    assert cast[uint64](item.displacement) == number(data, cursor + 32, 8)
  cursor += 40 + int(size)
assert cursor == data.len
echo "62550 operand-shape witnesses, both owned decode profiles"
