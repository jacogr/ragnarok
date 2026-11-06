# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Direct read-body ABI control for the same copied request on ARM64 and x86-64.

import std/[assertions, syncio]
import ../../src/pvm/[machine, program]
import ../../src/pvm/internal/[native_ir, native_platform, native_read_body]
when NativeCheckedReadEnabled:
  import std/envvars
  when defined(pvmX86Jit):
    import ../../src/pvm/internal/x86_jit
  else:
    import ../../src/pvm/internal/arm64_jit

proc readBody(): NativeReadBody =
  ## Use genuine decoded operands for a folded noop, four body operations and checked fallthrough.
  let wire = [0'u8, 0, 18,
    2, 124, 0x11, 2, 0, 1, 149, 0x11, 0, 0, 1, 129, 0x12, 0xff,
    130, 0x54, 1, 0, 0x43, 0x48, 0x03]
  let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  let owner = decoded.value
  let noop = instruction(owner, CodeAddress(0))
  let terminal = instruction(owner, CodeAddress(16))
  assert noop.error == ProgramError.None and noop.value.opcode == 2
  assert terminal.error == ProgramError.None and terminal.value.opcode == 1
  assert instructionTargetStartsBlock(terminal)
  result = initNativeReadBody(40, 45, 10, 15, 1)
  assert result.info.epoch == 1 and result.info.terminal == 45 and not result.complete
  for index, pc in [1'u32, 6, 11, 14]:
    # Bind copied relative addresses and aliases through the ordinary instruction decoder.
    let inst = instruction(owner, CodeAddress(pc))
    assert inst.error == ProgramError.None
    let operation = NativeOperation(opcode: inst.value.opcode,
      slots: instructionRegisters(inst), immediate: uint64(inst.value.x))
    if index == 0:
      assert not addReadBodyOperation(result, 42, 11, operation)
    assert addReadBodyOperation(result, uint32(41+index), uint32(11+index), operation)
  assert result.complete and result.len == 4

let body = readBody()
when NativeCheckedReadEnabled:
  if getEnv("RAGNAROK_PVM_CHECKED_READ_BODY_DUMP") == "1":
    # Emit exact leaf bytes without creating or entering an executable image.
    when defined(pvmX86Jit):
      let instructions = x86CheckedReadInstructions(body)
      assert instructions.len in 1..NativeImageByteLimit
      var bytes = newString(instructions.len)
      for i in 0..<instructions.len:
        bytes[i] = char(instructions[i])
    else:
      let words = armCheckedReadInstructions(body)
      assert words.len in 1..(NativeImageByteLimit div 4)
      var bytes = newString(words.len*4)
      for i in 0..<words.len:
        for part in 0..<4:
          bytes[i*4+part] = char((words[i] shr (part*8)) and 0xff'u32)
    stdout.write(bytes)
    quit 0
  let image = lowerNativeReadBody(body)
  assert image.ready and image.kind == NativeKind.CheckedReadBody
  assert image.codeBytes > 0 and image.codeBytes <= uint64(NativeImageByteLimit)
  when defined(pvmX86Jit):
    # The same deterministic emitter and fixture supply the dump and executable publication.
    assert image.codeBytes == uint64(x86CheckedReadInstructions(body).len)
  # The first region clips away a protected byte. The first two readable extents have their exact widths.
  var byteRegion = [0xa5'u8, 0x80]
  var signedRegion = [1'u8, 0, 0, 0x80]
  var wideRegion = [0x10'u8, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe]
  var context = [initNativeReadRegion(0xffff'u64, byteRegion),
    initNativeReadRegion(0x1007f'u64, signedRegion),
    initNativeReadRegion(0x20000'u64, wideRegion)]
  var initial = default(RegisterFile)
  for index in 0..<initial.len:
    initial[index] = RegisterValue(0x1234567800000000'u64+uint64(index))
  initial[1] = RegisterValue(0x00000001fffffffe'u64) # Low32 + 0x10002 wraps to 0x10000.
  initial[5] = RegisterValue(0x20000)
  var expected = initial
  expected[1] = RegisterValue(0x10080) # U8 reads old r1 before replacing its own base.
  expected[2] = RegisterValue(0xffffffff80000001'u64) # S32 uses the staged r1 with offset -1.
  expected[4] = RegisterValue(0xfedcba9876543210'u64)
  var registers = initial
  assert enterNativeReadBody(image, registers, context)
  for index in 0..<registers.len:
    assert uint64(registers[index]) == uint64(expected[index])
  # Shorten only the final extent. Earlier guards and scalar work still succeed, but cannot commit.
  context[2] = initNativeReadRegion(0x20000'u64, wideRegion.toOpenArray(0, 6))
  registers = initial
  assert not enterNativeReadBody(image, registers, context)
  for index in 0..<registers.len:
    assert uint64(registers[index]) == uint64(initial[index])
  assert byteRegion == [0xa5'u8, 0x80] and signedRegion == [1'u8, 0, 0, 0x80]
  assert wideRegion == [0x10'u8, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe]
  echo "PVM_CHECKED_READ_BODY_OK"
else:
  # Read-off profiles still decode the same bounded copied body.
  assert body.complete and body.len == 4
