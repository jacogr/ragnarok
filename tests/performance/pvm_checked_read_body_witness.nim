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
    import ../../src/pvm/step
    import ../../src/pvm/gas/gas
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

when NativeCheckedReadEnabled and defined(pvmX86Jit):
  proc windowFixture(): tuple[code: Program, body: NativeReadBody] =
    ## Two independent U8/U64 reads bracket a mixed-width group with a stable base.
    let wire = [0'u8, 0, 17,
      2, 124, 0x50, 124, 0x12, 0xf0, 129, 0x13, 0xf4, 130, 0x14, 0xf8,
      130, 0x76, 1, 50, 8, 0x4b, 0xd2, 0]
    let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
    assert decoded.error == ProgramError.None
    let code = decoded.value
    var windowBody = initNativeReadBody(40, 46, 10, 16, 1)
    for index, pc in [1'u32, 3, 6, 9, 12]:
      # Feed the same decoded guest operands to the body and to the checked interpreter.
      let inst = instruction(code, CodeAddress(pc))
      assert inst.error == ProgramError.None
      let operation = NativeOperation(opcode: inst.value.opcode,
        slots: instructionRegisters(inst), immediate: uint64(inst.value.x))
      assert addReadBodyOperation(windowBody, uint32(41+index), uint32(11+index), operation)
    assert windowBody.complete and windowBody.len == 5
    let selected = nativeReadWindow(windowBody, 127)
    assert selected.base == 1 and selected.first == 0xfffffff0'u32 and selected.length == 16
    result = (code, windowBody)

  proc sameRegisters(actual, expected: RegisterFile) =
    ## Check every slot so a premature commit cannot hide behind the failed destination.
    for index in 0..<actual.len:
      assert uint64(actual[index]) == uint64(expected[index])

  proc windowOracles() =
    ## Compare wrapped and split-readable cases while keeping one real native image.
    let fixture = windowFixture()
    let image = lowerNativeReadBody(fixture.body)
    assert image.ready and image.kind == NativeKind.CheckedReadBody and image.codeBytes == 525
    let groupBytes = [0x80'u8, 0xaa, 0xbb, 0xcc, 1, 0, 0, 0x80,
      0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe]
    let otherBytes = [0x7f'u8, 0, 0, 0, 0, 0, 0, 0,
      0xef, 0xcd, 0xab, 0x89, 0x67, 0x45, 0x23, 0x01]
    var group = groupBytes
    var other = otherBytes
    var initial = default(RegisterFile)
    for index in 0..<initial.len:
      # Every input slot has an independent value before the explicit base overrides.
      initial[index] = RegisterValue(0x1234567800000000'u64+uint64(index))
    initial[1] = RegisterValue(0x1234567800010010'u64)
    initial[5] = RegisterValue(0x20000)
    initial[7] = RegisterValue(0x20008)
    initial[8] = RegisterValue(0xffff0000)
    var expected = initial
    expected[0] = RegisterValue(0x7f)
    expected[2] = RegisterValue(0x80)
    expected[3] = RegisterValue(0xffffffff80000001'u64)
    expected[4] = RegisterValue(0xfedcba9876543210'u64)
    expected[6] = RegisterValue(0x0123456789abcdef'u64)
    var context = [initNativeReadRegion(0x10000'u64, group),
      initNativeReadRegion(0x20000'u64, other), default(NativeReadRegion)]
    var registers = initial
    assert enterNativeReadBody(image, registers, context)
    sameRegisters(registers, expected)

    # The last legal clipped start fits exactly. A one-byte-short extent must refuse.
    var edge = initial
    edge[1] = RegisterValue(0xffffffff'u64)
    var edgeExpected = expected
    edgeExpected[1] = edge[1]
    context[0] = initNativeReadRegion(0xffffffef'u64, group)
    registers = edge
    assert enterNativeReadBody(image, registers, context)
    sameRegisters(registers, edgeExpected)
    context[0] = initNativeReadRegion(0xffffffef'u64, group.toOpenArray(0, 14))
    registers = edge
    assert not enterNativeReadBody(image, registers, context)
    sameRegisters(registers, edge)

    # All reads fit separately across the page boundary. The hull refuses after the first load.
    var split = initial
    split[1] = RegisterValue(0x11008)
    context = [initNativeReadRegion(0x10ff8'u64, group.toOpenArray(0, 7)),
      initNativeReadRegion(0x11000'u64, group.toOpenArray(8, 15)),
      initNativeReadRegion(0x20000'u64, other)]
    registers = split
    assert not enterNativeReadBody(image, registers, context)
    sameRegisters(registers, split)
    var pages = [PageImage(index: PageIndex(16), access: PageAccess.ReadOnly),
      PageImage(index: PageIndex(17), access: PageAccess.ReadWrite),
      PageImage(index: PageIndex(32), access: PageAccess.ReadOnly)]
    for index in 0..<8:
      # The interpreter receives the same bytes in two genuine differently permitted pages.
      pages[0].bytes[4088+index] = group[index]
      pages[1].bytes[index] = group[8+index]
    for index in 0..<other.len:
      pages[2].bytes[index] = other[index]
    let memory = captureMemory(pages, PageLimit(3))
    assert memory.error == MachineError.None
    let source = captureMachine(fixture.code, memory.value, MachineInfo(pc: CodeAddress(0),
      gas: MachineGas(100000), registers: split))
    assert source.error == MachineError.None
    let checked = execute(source.value, ExecutionStepLimit(16), GasCycleLimit(1000))
    assert checked.error == StepError.None and checked.value.exit == StepExit.Halt
    assert checked.value.backend == PvmBackend.Interpreted
    var splitExpected = expected
    splitExpected[1] = split[1]
    sameRegisters(machineInfo(checked.value.machine).value.registers, splitExpected)
    let finalMemory = memoryOf(checked.value.machine).value
    for page in pages:
      # Checked replay accepts the split layout and preserves its original permissions and bytes.
      let observed = pageImage(finalMemory, page.index)
      assert observed.error == MachineError.None and observed.value.access == page.access
      assert observed.value.bytes == page.bytes

    # The hull now passes. A later unrelated U64 refusal still cannot publish the staged results.
    context = [initNativeReadRegion(0x10000'u64, group),
      initNativeReadRegion(0x20000'u64, other.toOpenArray(0, 14)), default(NativeReadRegion)]
    registers = initial
    assert not enterNativeReadBody(image, registers, context)
    sameRegisters(registers, initial)
    context[1] = initNativeReadRegion(0x20000'u64, other)
    assert enterNativeReadBody(image, registers, context)
    sameRegisters(registers, expected)
    assert group == groupBytes and other == otherBytes
    echo "PVM_CHECKED_READ_WINDOW_OK"

let body = readBody()
when NativeCheckedReadEnabled:
  let dump = getEnv("RAGNAROK_PVM_CHECKED_READ_BODY_DUMP")
  if dump == "1" or (defined(pvmX86Jit) and dump == "window"):
    # Emit exact leaf bytes without creating or entering an executable image.
    when defined(pvmX86Jit):
      let instructions = x86CheckedReadInstructions(
        if dump == "window": windowFixture().body else: body)
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
    assert nativeReadWindow(body, 127).length == 0
    assert image.codeBytes == 509
    assert image.codeBytes == uint64(x86CheckedReadInstructions(body).len)
  # The first region clips a protected byte. The first two readable extents fit their exact widths.
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
  when defined(pvmX86Jit):
    windowOracles()
else:
  # Read-off profiles still decode the same bounded copied body.
  assert body.complete and body.len == 4
