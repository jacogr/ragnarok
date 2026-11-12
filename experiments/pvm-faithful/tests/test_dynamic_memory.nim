# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Replay the frozen independently executed PolkaVM endpoint corpus and test mutable host access.
## The 90-row corpus comes from tests/reference/polkavm_memory, never from this port.

import std/[assertions, syncio, envvars]
import ../dynamic_memory

proc word(data: string, offset, width: int): uint64 =
  ## Decode the fixed test format after the caller has checked the complete corpus extent.
  result = 0
  for index in 0..<width:
    result = result or (uint64(byte(data[offset+index])) shl (8*index))

proc apply(memory: var DynamicMemory, opcode: byte, address: uint32): Access =
  ## Select only scalar memory semantics; no production decoder or interpreter is linked.
  case opcode
  of 52, 53: result = load[1](memory, address)
  of 54, 55: result = load[2](memory, address)
  of 56, 57: result = load[4](memory, address)
  of 58: result = load[8](memory, address)
  of 59: result = store[1](memory, address, 99)
  of 60: result = store[2](memory, address, 99)
  of 61: result = store[4](memory, address, 99)
  of 62: result = store[8](memory, address, 99)
  else: assert false, "foreign memory witness opcode"
  if result.kind == AccessKind.Ok:
    # The instruction layer, not the memory container, owns signed extension.
    case opcode
    of 53: result.value = cast[uint64](int64(cast[int8](byte(result.value))))
    of 55: result.value = cast[uint64](int64(cast[int16](uint16(result.value))))
    of 57: result.value = cast[uint64](int64(cast[int32](uint32(result.value))))
    else: discard

if getEnv("RAGNAROK_FAITHFUL_ASSERT") == "1":
  assert false, "faithful assertion control"

var data = ""
try:
  # Missing independent evidence is a failed test setup, never a skipped corpus.
  data = readFile("tests/fixtures/pvm-memory-boundary.bin")
except:
  quit 2
assert data.len == 2262 and data[0..7] == "PVMMEM01" and word(data, 8, 4) == 90
for row in 0..<90:
  # Each independent record specifies operation, exact fault and final observed scalar/tail bytes.
  let at = 12+25*row
  let address = uint32(word(data, at, 8))
  let mapping = byte(data[at+8])
  let opcode = byte(data[at+9])
  var memory = default(DynamicMemory)
  memory.reset(4096)
  if mapping != 0:
    assert memory.mapZero(0xfffff000'u32, 4096, false)
    var initial = default(array[4096, byte])
    for index in 0..<initial.len: initial[index] = 7
    assert memory.write(0xfffff000'u32, initial)
    if mapping == 2: assert memory.protect(0xfffff000'u32, 4096, true)
  let answer = apply(memory, opcode, address)
  assert ord(answer.kind) == int(byte(data[at+10]))
  assert answer.page == uint32(word(data, at+11, 4))
  let a0 = if opcode <= 58 and answer.kind == AccessKind.Ok: answer.value else: 99'u64
  assert a0 == word(data, at+15, 8)
  if mapping != 0:
    var posterior = default(array[4096, byte])
    assert memory.read(0xfffff000'u32, posterior)
    assert posterior[4094] == byte(data[at+23]) and posterior[4095] == byte(data[at+24])
    let widths = [1, 1, 2, 2, 4, 4, 8, 1, 2, 4, 8]
    let width = widths[int(opcode)-52]
    for index in 0..<4096:
      let absolute = 0xfffff000'u64+uint64(index)
      var expected = 7'u8
      if opcode >= 59 and answer.kind == AccessKind.Ok and absolute >= uint64(address) and
          absolute-uint64(address) < uint64(width):
        expected = byte((99'u64 shr (8*int(absolute-uint64(address)))) and 255)
      assert posterior[index] == expected

block:
  # A failed crossing store preserves the first page; repairing the mapping permits an exact retry.
  var memory = default(DynamicMemory)
  memory.reset(4096)
  assert memory.mapZero(0x10000, 4096, false)
  assert store[1](memory, 0x10fff, 0xaa).kind == AccessKind.Ok
  let missing = store[8](memory, 0x10fff, 0x8877665544332211'u64)
  assert missing.kind == AccessKind.Segfault and missing.page == 0x11000 and not missing.readOnly
  assert load[1](memory, 0x10fff).value == 0xaa
  assert memory.mapZero(0x11000, 4096, true)
  let protected = store[8](memory, 0x10fff, 0x8877665544332211'u64)
  assert protected.kind == AccessKind.Segfault and protected.page == 0x11000 and protected.readOnly
  assert load[1](memory, 0x10fff).value == 0xaa
  assert memory.protect(0x11000, 4096, false)
  assert store[8](memory, 0x10fff, 0x8877665544332211'u64).kind == AccessKind.Ok
  assert load[8](memory, 0x10fff).value == 0x8877665544332211'u64
  memory.reset(4096)
  assert load[1](memory, 0x10fff).kind == AccessKind.Segfault

echo "faithful dynamic memory passed: 90 upstream endpoints and crossing retry"
