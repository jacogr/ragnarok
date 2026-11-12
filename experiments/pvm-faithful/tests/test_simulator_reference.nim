# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compare Full(L2Hit) costs and block lifecycle after every instruction, not only final totals.

import std/[assertions, syncio, envvars]
import ../[decode, simulator]

proc word(data: string, at, length: int): uint64 =
  ## Decode bounded fixed-width oracle framing independently of candidate gas scheduling.
  assert at >= 0 and at <= data.len and length >= 0 and length <= data.len-at
  result = 0
  for index in 0..<length: result = result or (uint64(byte(data[at+index])) shl (8*index))

var data = ""
try:
  data = readFile("build/pvm-faithful/simulator.bin")
except:
  quit 2
assert data.len >= 12 and data[0..7] == "PVFGAS01"
let count = int(word(data, 8, 4))
assert count == 1152
var cursor = 12
let corrupt = getEnv("RAGNAROK_FAITHFUL_CORRUPT") == "1"
for sample in 0..<count:
  let codeLength = int(word(data, cursor, 4))
  cursor += 4
  assert codeLength == 256
  var code = newSeq[byte](codeLength)
  for index in 0..<code.len: code[index] = byte(data[cursor+index])
  cursor += code.len
  let steps = int(word(data, cursor, 4))
  cursor += 4
  assert steps == 161
  var sim = newSimulator(code)
  var unusedCost = 0'u32
  assert sim.atBlockStart and not sim.takeBlockCost(unusedCost)
  for step in 0..<steps:
    let value = [word(data, cursor, 8), word(data, cursor+8, 8)]
    let offset = uint32(word(data, cursor+16, 4))
    let length = uint32(byte(data[cursor+20]))
    let expectedPresent = byte(data[cursor+21]) == 1
    let expectedCost = uint32(word(data, cursor+22, 4)) xor (if corrupt and sample == 0 and step ==
        0: 1'u32 else: 0'u32)
    let expectedStart = byte(data[cursor+26]) == 1
    let parsed = ParsedInstruction(instruction: decode(value, offset, length), offset: offset,
        nextOffset: offset+length)
    sim.visit(parsed)
    var cost = 0'u32
    let present = sim.takeBlockCost(cost)
    if present != expectedPresent or cost != expectedCost:
      echo "gas mismatch sequence=", sample, " step=", step, " opcode=", ord(
          parsed.instruction.opcode),
        " actual=", cost, " expected=", expectedCost
    assert present == expectedPresent and cost == expectedCost, "faithful simulator gas mismatch"
    assert sim.atBlockStart == expectedStart, "faithful simulator lifecycle mismatch"
    cursor += 27
  assert sim.atBlockStart
assert cursor == data.len
echo "faithful full simulator reference passed: ", count, " sequences"
