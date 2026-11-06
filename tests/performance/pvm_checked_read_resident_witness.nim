# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Compare the same checked-read certificate through the stack and resident x86 leaves.

import std/[assertions, envvars, syncio]
import ../../src/pvm/[machine, program]
import ../../src/pvm/internal/[native_ir, native_platform, native_read_body, x86_jit]

static:
  assert NativeCheckedReadEnabled and defined(pvmX86Jit) and defined(pvmX86ResidentProof)

proc readBody(extraWrites: range[0..4]): NativeReadBody =
  ## Add decoded writes before the final guarded load to reach six or seven dirty slots.
  var code = @[2'u8, 124, 0x11, 2, 0, 1, 149, 0x11, 0, 0, 1, 129, 0x12, 0xff]
  var starts = @[1, 6, 11]
  let extra = [[149'u8, 0x33, 1], [51'u8, 6, 0x26], [51'u8, 7, 0x37], [51'u8, 8, 0x48]]
  for index in 0..<extraWrites:
    starts.add(code.len)
    code.add(extra[index])
  starts.add(code.len)
  code.add([130'u8, 0x54])
  let terminalPc = code.len
  code.add([1'u8, 0])
  var wire = @[0'u8, 0, byte(code.len)]
  wire.add(code)
  var bitmask = newSeq[byte]((code.len+7) div 8)
  bitmask[0] = 1 # The folded leading noop is itself an instruction start.
  for pc in starts:
    bitmask[pc div 8] = bitmask[pc div 8] or (1'u8 shl (pc mod 8))
  for pc in terminalPc..<code.len:
    bitmask[pc div 8] = bitmask[pc div 8] or (1'u8 shl (pc mod 8))
  wire.add(bitmask)
  let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  let owner = decoded.value
  let noop = instruction(owner, CodeAddress(0))
  let terminal = instruction(owner, CodeAddress(uint32(terminalPc)))
  assert noop.error == ProgramError.None and noop.value.opcode == 2
  assert terminal.error == ProgramError.None and terminal.value.opcode == 1
  assert instructionTargetStartsBlock(terminal)
  result = initNativeReadBody(40, uint32(41+starts.len), 10, uint32(11+starts.len), 1)
  for index, pc in starts:
    let inst = instruction(owner, CodeAddress(uint32(pc)))
    assert inst.error == ProgramError.None
    let op = NativeOperation(opcode: inst.value.opcode, slots: instructionRegisters(inst),
      immediate: uint64(inst.value.x))
    assert addReadBodyOperation(result, uint32(41+index), uint32(11+index), op)
  assert result.complete and result.len == starts.len

proc sameRegisters(actual, expected: RegisterFile) =
  for index in 0..<actual.len:
    assert uint64(actual[index]) == uint64(expected[index])

proc verifyBody(body: NativeReadBody, extraWrites: range[0..4]) =
  let baselineBytes = x86CheckedReadStackInstructions(body)
  let selectedBytes = x86CheckedReadInstructions(body)
  case extraWrites
  of 0:
    # PUSH RBX; MOV RBX,[RDI+8]; PUSH RBP; PUSH R12; MOV R10,RSI.
    let entry = [0x53'u8, 0x48, 0x8b, 0x5f, 8, 0x55, 0x41, 0x54, 0x49, 0x89, 0xf2]
    assert baselineBytes.len == 509 and selectedBytes.len == 474
    for index, expected in entry: assert selectedBytes[index] == expected
  of 3:
    # The sixth mapped lane reaches R15, with R12 initialized for the ADD of old r3.
    assert selectedBytes != baselineBytes
    let entry = [0x53'u8, 0x48, 0x8b, 0x5f, 8, 0x55, 0x41, 0x54, 0x4c, 0x8b, 0x67, 24,
      0x41, 0x55, 0x41, 0x56, 0x41, 0x57, 0x49, 0x89, 0xf2]
    for index, expected in entry: assert selectedBytes[index] == expected
  of 4:
    assert selectedBytes == baselineBytes # A seventh dirty slot keeps the original stack policy.
  else: assert false

  let baseline = lowerNativeReadBodyStackProof(body)
  let selected = lowerNativeReadBody(body)
  assert isReadBody(baseline) and isReadBody(selected)
  assert baseline.codeBytes == uint64(baselineBytes.len)
  assert selected.codeBytes == uint64(selectedBytes.len)
  var byteRegion = [0xa5'u8, 0x80]
  var signedRegion = [1'u8, 0, 0, 0x80]
  var wideRegion = [0x10'u8, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe]
  var context = [initNativeReadRegion(0xffff'u64, byteRegion),
    initNativeReadRegion(0x1007f'u64, signedRegion), default(NativeReadRegion)]
  var initial = default(RegisterFile)
  for index in 0..<initial.len:
    initial[index] = RegisterValue(0x1234567800000000'u64+uint64(index))
  initial[1] = RegisterValue(0x00000001fffffffe'u64)
  initial[5] = RegisterValue(0x20000)
  var expected = initial
  expected[1] = RegisterValue(0x10080) # The first U8 uses old r1, then replaces its aliased base.
  expected[2] = RegisterValue(0xffffffff80000001'u64) # The S32 base reads the new r1.
  expected[4] = RegisterValue(0xfedcba9876543210'u64)
  if extraWrites >= 3:
    expected[3] = RegisterValue(0x1234567800000004'u64) # The mapped ADD consumes the original r3.
    expected[6] = RegisterValue(0x26)
    expected[7] = RegisterValue(0x37)
  if extraWrites == 4:
    expected[8] = RegisterValue(0x48)

  for phase in 0..2:
    # The same images must succeed, refuse the final U64 after earlier work, then recover.
    let success = phase != 1
    if success:
      context[2] = initNativeReadRegion(0x20000'u64, wideRegion)
    else:
      context[2] = initNativeReadRegion(0x20000'u64, wideRegion.toOpenArray(0, 6))
    var original = initial
    var candidate = initial
    var production = initial
    assert enterNativeReadBodyAbiProof(baseline, original, context) == success
    assert enterNativeReadBodyAbiProof(selected, candidate, context) == success
    assert enterNativeReadBody(selected, production, context) == success
    sameRegisters(candidate, original)
    sameRegisters(production, candidate)
    if success: sameRegisters(candidate, expected)
    else: sameRegisters(candidate, initial)
  assert byteRegion == [0xa5'u8, 0x80] and signedRegion == [1'u8, 0, 0, 0x80]
  assert wideRegion == [0x10'u8, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe]

let dump = getEnv("RAGNAROK_PVM_CHECKED_READ_RESIDENT_DUMP")
if dump != "":
  let encoded = case dump
    of "stack": x86CheckedReadStackInstructions(readBody(0))
    of "resident": x86CheckedReadInstructions(readBody(0))
    of "six": x86CheckedReadInstructions(readBody(3))
    of "seven": x86CheckedReadInstructions(readBody(4))
    of "seven-stack": x86CheckedReadStackInstructions(readBody(4))
    else: default(seq[byte])
  assert encoded.len in 1..NativeImageByteLimit
  var bytes = newString(encoded.len)
  for index in 0..<encoded.len: bytes[index] = char(encoded[index])
  stdout.write(bytes)
  quit 0

verifyBody(readBody(0), 0)
verifyBody(readBody(3), 3)
verifyBody(readBody(4), 4)
echo "PVM_CHECKED_READ_RESIDENT_OK"
