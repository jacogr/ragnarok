# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise live static fusion through ordinary prepared calls and the real asynchronous runtime.
## A two-block loop leaves a tiny pure prefix intact, trains once, and has a paid memory exit.

import std/assertions
import ../../src/codec/natural
import ../../src/pvm/[program, machine, step]
import ../../src/pvm/internal/[native_pipeline, native_fusion, native_platform, native_ir]

proc fusionGuest(): Program =
  ## The two loop blocks are independently priced. One has a load after a store,
  ## and the other has an ordinary static branch back to the first.
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  template emit(bytes: openArray[byte]) =
    starts.add(code.len)
    for value in bytes: code.add(value)
  template jump(op: openArray[byte], destination: int) =
    let distance = cast[uint32](int32(destination-code.len))
    starts.add(code.len)
    for value in op: code.add(value)
    for index in 0..<4: code.add(byte((distance shr (index*8)) and 255))
  emit([149'u8, 0x77, 1]) # Small incumbent pure prefix.
  emit([149'u8, 0x88, 1])
  emit([120'u8, 0x50, 1]) # Mark the writable page before native entry.
  let first = code.len+5
  jump([40'u8], first)
  assert code.len == first
  emit([2'u8]) # Folded no-op still consumes an original attempt.
  emit([120'u8, 0x50, 0]) # Store byte R0,[R5].
  emit([124'u8, 0x61, 0]) # Read byte R1,[R6]. A missing page is a paid fault.
  emit([149'u8, 0x22, 1]) # One completed iteration per pass.
  let second = code.len+5
  jump([40'u8], second)
  assert code.len == second
  emit([149'u8, 0x99, 1])
  jump([171'u8, 0xc2], first) # Continue while R2 != R12.
  emit([50'u8, 3]) # Dynamic halt sentinel in R3.
  var wire = @[0'u8, 0]
  let size = encode(JamNatural(uint64(code.len)))
  for index in 0..<size.len: wire.add(size.bytes[index])
  for value in code: wire.add(value)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for value in mask: wire.add(value)
  let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(128), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  decoded.value

proc assertSameFusionResult(actual, expected: StepResult) =
  ## Checked output owns the independent guest state and attempt accounting oracle.
  assert actual.error == expected.error, "paired step error"
  if expected.error == StepError.None:
    assert actual.value.exit == expected.value.exit, "paired guest exit"
    if expected.value.exit == StepExit.Fault:
      assert uint64(actual.value.faultPage) == uint64(expected.value.faultPage)
    assert machineInfo(actual.value.machine).value == machineInfo(expected.value.machine).value, "paired CPU"
    let observed = memoryOf(actual.value.machine).value
    let reference = memoryOf(expected.value.machine).value
    let observedPages = pageIndices(observed).value
    let referencePages = pageIndices(reference).value
    assert observedPages == referencePages
    for page in referencePages:
      assert pageImage(observed, page).value == pageImage(reference, page).value, "paired memory bytes"

proc checkShortFusionEntries() =
  ## A static predecessor can enter from checked dispatch. Its terminal leaf
  ## stays checked on a direct visit, but must still execute inside the chain.
  var blocks = [
    NativeFusionBlock(header: 4, terminal: 5, span: 1, price: 3,
      targets: [10'u32, NativeEntryFailure], branch: NativeOperation(opcode: 40)),
    NativeFusionBlock(header: 10, terminal: 12, first: 1, span: 2, price: 7,
      targets: [NativeEntryFailure, NativeEntryFailure])]
  blocks[1].operations[0] = NativeOperation(opcode: 51, immediate: 247)
  let shortImage = lowerNativeFusion(blocks)
  assert nativeFusionEntry(shortImage, 0) and nativeFusionEntry(shortImage, 1)
  assert nativeFusionDispatchEntry(shortImage, 0)
  assert not nativeFusionDispatchEntry(shortImage, 1)
  var registers = default(RegisterFile)
  var context = NativeFusionContext(gas: 100, remaining: 16)
  let next = enterNativeFusion(shortImage, 0, registers, context)
  let receipt = nativeFusionExit(blocks, 4, next, 100, 16, context)
  assert receipt.valid and receipt.paidHeader == 11 and receipt.attempted == 3
  assert next == 12 and context.path == 0x0102 and context.gas == 90 and context.remaining == 13
  assert uint64(registers[0]) == 247

  # The same two blocks can form a cycle with repeated native links.
  blocks[1].targets[0] = 4
  blocks[1].branch = NativeOperation(opcode: 40)
  let cyclicImage = lowerNativeFusion(blocks)
  assert nativeFusionDispatchEntry(cyclicImage, 0) and nativeFusionDispatchEntry(cyclicImage, 1)

proc runStaticFusion*() =
  ## Exercise natural selection and exact paid/unpaid exits with changed public inputs.
  let program = fusionGuest()
  let runtime = newNativeRuntime()
  try:
    assert start(runtime)
  except:
    assert false, "static fusion runtime failed to start"
  let jit = newPreparedProgram(program, defaultPreparedLimits(), PvmBackend.Jit, runtime)
  let checked = newPreparedProgram(program, defaultPreparedLimits(), PvmBackend.Interpreted)
  assert jit.error == PreparationError.None and checked.error == PreparationError.None
  let page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)
  let memory = captureMemory([page], PageLimit(2)).value
  var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(4000000))
  info.registers[0] = RegisterValue(165)
  info.registers[3] = RegisterValue(0xffff0000'u64)
  info.registers[5] = RegisterValue(65536)
  info.registers[6] = RegisterValue(65536)
  info.registers[12] = RegisterValue(90000)
  let source = captureMachine(program, memory, info).value
  let limit = ExecutionStepLimit(2000000)
  let expected = execute(source, limit, checked.value)
  assert expected.error == StepError.None and expected.value.exit == StepExit.Halt, "training oracle must halt"
  for sample in 0..2:
    # Wait only in the witness, outside invocation, to distinguish queued work from use.
    let outcome = execute(source, limit, jit.value)
    assertSameFusionResult(outcome, expected)
    waitNativeCompiler(runtime)
    let state = preparedInfo(jit.value).value
    if sample == 0: assert state.nativeOperations == 0
    if sample == 1: assert state.nativeOperations < 16 and state.nativeFragments == 2, "training publication"
    if sample == 2: assert state.nativeOperations > NativeFusionTrainingFloor, "native fused reuse"

  # A small live quota and low gas enter checked workers at the exact boundary.
  for budget in [4096'u64, 4097, 4098, 4099]:
    let before = preparedInfo(jit.value).value.nativeOperations
    let quota = ExecutionStepLimit(budget)
    let outcome = execute(source, quota, jit.value)
    assert outcome.error == StepError.StepLimitExceeded
    assertSameFusionResult(outcome, execute(source, quota, checked.value))
    assert preparedInfo(jit.value).value.nativeOperations > before+2, "native short quota"
  info.gas = MachineGas(1000)
  let short = captureMachine(program, memory, info).value
  let gasExit = execute(short, limit, jit.value)
  assert gasExit.error == StepError.None and gasExit.value.exit == StepExit.OutOfGas
  assertSameFusionResult(gasExit, execute(short, limit, checked.value))

  # The prefix dirties the page. The linked store must commit before the paid
  # read fault returns with the same reservation and original guest PC.
  info.gas = MachineGas(4000000)
  info.registers[6] = RegisterValue(69632)
  let missing = captureMachine(program, memory, info).value
  let beforeFault = preparedInfo(jit.value).value.nativeOperations
  let fault = execute(missing, limit, jit.value)
  assert preparedInfo(jit.value).value.nativeOperations == beforeFault+4, "native paid prefix"
  assert fault.error == StepError.None and fault.value.exit == StepExit.Fault
  assertSameFusionResult(fault, execute(missing, limit, checked.value))
  assert machineInfo(fault.value.machine).value.blockCharged
  assert load(memoryOf(fault.value.machine).value, MemoryAddress(65536),
    AccessWidth(1)).value == RegisterValue(165)

  # Supply the missing page and resume the exact paid suffix through the same cached owner.
  let extra = PageImage(index: PageIndex(17), access: PageAccess.ReadOnly)
  let repaired = withPage(memoryOf(fault.value.machine).value, extra)
  assert repaired.error == MachineError.None
  let resumed = withMemory(fault.value.machine, repaired.value)
  assert resumed.error == MachineError.None
  assertSameFusionResult(execute(resumed.value, limit, jit.value),
    execute(resumed.value, limit, checked.value))
  assert close(runtime)
  checkShortFusionEntries()
