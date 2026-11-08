# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal GP store/load widths and grouped pointer choices stay checked until shared memory lowering exists.

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, step]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/internal/handler_stream

const
  # Columns are load_u8, load_i8, load_u16, load_i16, load_u32, load_i32, load_u64.
  # Rows describe the literal bytes remaining after store_u8/u16/u32/u64 of FEDCBA98F654B281.
  # No production width, direction, sign-extension or opcode-support helper derives these answers.
  Loaded = [
    [0x81'u64, 0xffffffffffffff81'u64, 0xe381'u64, 0xffffffffffffe381'u64,
      0x8745e381'u64, 0xffffffff8745e381'u64, 0xefcdab898745e381'u64],
    [0x81'u64, 0xffffffffffffff81'u64, 0xb281'u64, 0xffffffffffffb281'u64,
      0x8745b281'u64, 0xffffffff8745b281'u64, 0xefcdab898745b281'u64],
    [0x81'u64, 0xffffffffffffff81'u64, 0xb281'u64, 0xffffffffffffb281'u64,
      0xf654b281'u64, 0xfffffffff654b281'u64, 0xefcdab89f654b281'u64],
    [0x81'u64, 0xffffffffffffff81'u64, 0xb281'u64, 0xffffffffffffb281'u64,
      0xf654b281'u64, 0xfffffffff654b281'u64, 0xfedcba98f654b281'u64]]
  Stored = [
    [0x81'u8, 0xe3, 0x45, 0x87, 0x89, 0xab, 0xcd, 0xef],
    [0x81'u8, 0xb2, 0x45, 0x87, 0x89, 0xab, 0xcd, 0xef],
    [0x81'u8, 0xb2, 0x54, 0xf6, 0x89, 0xab, 0xcd, 0xef],
    [0x81'u8, 0xb2, 0x54, 0xf6, 0x98, 0xba, 0xdc, 0xfe]]

proc source(store, load: byte, grouped: bool): Program =
  ## The first pair selects a shared window or individual guards; the second supplies an admission window.
  let parts = [@[40'u8, 5, 0, 0, 0], @[store, 0x18'u8, 0, 0, 0, 0],
    @[load, (if grouped: 0x12'u8 else: 0x62'u8), 0, 0, 0, 0],
    @[store, (if grouped: 0x18'u8 else: 0x78'u8), (if grouped: 16'u8 else: 0'u8), 0, 0, 0],
    @[load, (if grouped: 0x19'u8 else: 0x79'u8), (if grouped: 16'u8 else: 0'u8), 0, 0, 0],
    @[149'u8, 0x44, 1], @[171'u8, 0x54, 0xe5, 0xff, 0xff, 0xff], @[50'u8, 0]]
  var code: seq[byte] = @[]
  var bitmap = default(array[5, byte])
  for part in parts:
    # Every literal instruction begins at a genuine marked source boundary.
    bitmap[code.len div 8] = bitmap[code.len div 8] or (1'u8 shl (code.len mod 8))
    for octet in part: code.add(octet)
  assert code.len == 40, "literal framing length"
  var raw = @[0'u8, 0, 40]
  for octet in code: raw.add(octet)
  for octet in bitmap: raw.add(octet)
  let decoded = decodeProgram(raw, CodeAddress(0), ProgramByteLimit(128), JumpCountLimit(0))
  assert decoded.error == ProgramError.None, "literal program decoding"
  decoded.value

proc checkWidths(store, load: int, grouped: bool) =
  ## Both plan permissions keep all literal width/grouping outcomes; these bare frames have no native session.
  let program = source(byte(120+store), byte(124+load), grouped)
  var image = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)
  for index in 0..<image.bytes.len: image.bytes[index] = 0xa5
  for index, value in [0x11'u8, 0xe3, 0x45, 0x87, 0x89, 0xab, 0xcd, 0xef]:
    image.bytes[index] = value
    image.bytes[16+index] = value
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(0xffff0000'u64)
  registers[1] = RegisterValue(65536)
  registers[5] = RegisterValue(20)
  registers[6] = RegisterValue(65536)
  registers[7] = RegisterValue(65552)
  registers[8] = RegisterValue(0xfedcba98f654b281'u64)
  registers[9] = RegisterValue(0x123456789abcdef0'u64)
  let initial = MachineInfo(pc: CodeAddress(0), gas: MachineGas(100000), registers: registers)
  var expectedRegisters = registers
  expectedRegisters[2] = RegisterValue(Loaded[store][load])
  expectedRegisters[4] = RegisterValue(20)
  expectedRegisters[9] = RegisterValue(Loaded[store][load])
  var expectedImage = image
  for index, value in Stored[store]:
    expectedImage.bytes[index] = value
    expectedImage.bytes[16+index] = value
  var checked = prepareFlatPlan(program, GasCycleLimit(100000), defaultFlatLimits(), false)
  assert checked.error == FlatError.None, "checked source preparation"
  var reference = newFlatFrame(checked.takeValue, [image], initial)
  var native = newFlatFrame(newFlatPlan(program, GasCycleLimit(100000)), [image], initial)
  runFlat(reference, 1000)
  runFlat(native, 1000)
  assert reference.reason == StepError.None and reference.exit == StepExit.Halt, "checked halt"
  assert native.reason == StepError.None and native.exit == StepExit.Halt, "native halt"
  assert reference.info.registers == expectedRegisters, "checked literal registers"
  assert native.info.registers == expectedRegisters, "native literal registers"
  # Full bookkeeping parity supplements the independent literal register and byte expectations.
  assert native.info == reference.info, "complete CPU bookkeeping parity"
  # One static entry, twenty six-operation bodies and one halt consume 122 source attempts.
  assert native.remaining == 878 and reference.remaining == 878, "literal source attempt count"
  checkFlatSource(native, [image])
  checkFlatSource(reference, [image])
  let actual = memoryImages(flatMemorySnapshot(native))
  let expected = memoryImages(flatMemorySnapshot(reference))
  assert actual.error == MachineError.None and expected.error == MachineError.None, "memory snapshot"
  assert actual.value == @[expectedImage], "native literal bytes"
  assert expected.value == @[expectedImage], "checked literal bytes"
  # This is checked memory semantics, not native mixed/window coverage; the feature obligation stays explicit.
  assert flatArmMixedStatistics(native) == default(array[4, uint64]), "unbound mixed route stays checked"
  assert flatArmMixedGroupStatistics(native) == default(array[3, uint64]), "no native memory window"
  assert flatArmStatistics(native) == default(array[5, uint64]), "no eager native publication or entry"

# Every store/load pairing runs with both pointer-window choices; answers remain literal.
for store in 0..<4:
  for load in 0..<7:
    for grouped in [false, true]: checkWidths(store, load, grouped)
echo "PVM memory rules passed (56 literal checked width/grouping routes)"
