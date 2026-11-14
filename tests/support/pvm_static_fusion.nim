# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise live static fusion through ordinary prepared calls and the real asynchronous runtime.
## A two-block loop leaves a tiny pure prefix intact, trains once, and has a paid memory exit.

import std/assertions
import ../../src/codec/natural
import ../../src/pvm/[program, machine, step]
import ../../src/pvm/internal/[native_pipeline, native_fusion, native_platform]

proc checkRepeatedFusionReceipt() =
  ## Warm a paid path, then exercise the same key with incorrect live debits and
  ## exit mode. A prior proof must never authorize different returned state.
  let blocks = [
    NativeFusionBlock(header: 10, terminal: 12, span: 2, price: 3, targets: [20'u32, 30]),
    NativeFusionBlock(header: 20, terminal: 23, span: 3, price: 7,
      targets: [high(uint32), high(uint32)], guards: 1)]
  var memo = default(NativeFusionReceipts)
  var state = NativeFusionContext(gas: 90, remaining: 95, visits: 2, paid: 1)
  state.path[0] = 0x0201 # Forward byte order records block one, then block two.
  let proven = checkNativeFusionExit(memo, blocks, 10, 21, 100, 100, state)
  assert proven.valid and proven.paidHeader == 21 and proven.attempted == 5 and proven.branches

  # Reuse the path with different starting budgets and the same exact debits.
  state.gas = 5
  state.remaining = 0
  assert checkNativeFusionExit(memo, blocks, 10, 21, 15, 5, state) == proven

  # Every malformed return must fail even after this source path was authorized.
  assert not checkNativeFusionExit(memo, blocks, 11, 21, 15, 5, state).valid
  assert not checkNativeFusionExit(memo, blocks, 10, 22, 15, 5, state).valid
  assert not checkNativeFusionExit(memo, blocks, 10, 21, 16, 5, state).valid
  assert not checkNativeFusionExit(memo, blocks, 10, 21, 15, 6, state).valid
  state.paid = 0
  assert not checkNativeFusionExit(memo, blocks, 10, 21, 15, 5, state).valid
  state.paid = 1
  assert checkNativeFusionExit(memo, blocks, 10, 21, 15, 5, state) == proven

proc checkLongFusionReceipts() =
  ## Word-boundary paths keep complete identity, exact debits and paid/unpaid exit modes.
  let blocks = [
    NativeFusionBlock(header: 10, terminal: 12, span: 2, price: 3,
      targets: [20'u32, 20], guards: 1),
    NativeFusionBlock(header: 20, terminal: 23, span: 3, price: 7,
      targets: [10'u32, 10], guards: 1)]
  var memo = default(NativeFusionReceipts)
  for count in [1, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64]:
    # Only supported lengths are constructed; the same controls run for each trial horizon.
    if count > NativeFusionVisitLimit: continue
    let debit = uint64((count div 2)*10+(if (count and 1) != 0: 3 else: 0))
    let attempts = uint64((count div 2)*5+(if (count and 1) != 0: 2 else: 0))
    let last = if (count and 1) != 0: 10'u32 else: 20'u32
    let next = if (count and 1) != 0: 20'u32 else: 10'u32
    var state = NativeFusionContext(gas: 1000-debit, remaining: 1000-attempts,
      visits: uint64(count), paid: 0)
    for index in 0..<count:
      # Forward tokens alternate two independently priced source blocks, including repeated visits.
      state.path[index div 8] = state.path[index div 8] or
        (uint64(1+(index and 1)) shl ((index and 7)*8))
    let proven = checkNativeFusionExit(memo, blocks, 10, next, 1000, 1000, state)
    assert proven.valid and proven.paidHeader == 0 and proven.attempted == uint32(attempts)
    assert proven.branches and proven.lastToken == (if (count and 1) != 0: 1'u32 else: 2'u32)
    if (count and 7) != 0:
      # A producer need not clear unwritten bytes from a previous longer entry.
      let word = count div 8
      state.path[word] = state.path[word] or (0xff'u64 shl ((count and 7)*8))
      assert checkNativeFusionExit(memo, blocks, 10, next, 1000, 1000, state) == proven
    let original = state.path
    let middle = count div 2
    state.path[middle div 8] = state.path[middle div 8] and
      not (255'u64 shl ((middle and 7)*8))
    assert not checkNativeFusionExit(memo, blocks, 10, next, 1000, 1000, state).valid
    state.path = original
    dec state.visits
    assert not checkNativeFusionExit(memo, blocks, 10, next, 1000, 1000, state).valid
    state.visits = uint64(count)
    state.paid = 1
    let paid = checkNativeFusionExit(memo, blocks, 10, last+1, 1000, 1000, state)
    assert paid.valid and paid.paidHeader == last+1 and paid.attempted == uint32(attempts)
    state.paid = 0
    assert not checkNativeFusionExit(memo, blocks, 10, last+1, 1000, 1000, state).valid
    state.visits = uint64(NativeFusionVisitLimit)+1
    assert not checkNativeFusionExit(memo, blocks, 10, next, 1000, 1000, state).valid
  var empty = NativeFusionContext(gas: 1000, remaining: 1000)
  empty.path[0] = high(uint64)
  let idle = checkNativeFusionExit(memo, blocks, 10, 10, 1000, 1000, empty)
  assert idle.valid and idle.lastToken == 0
  empty.paid = 1
  assert not checkNativeFusionExit(memo, blocks, 10, 10, 1000, 1000, empty).valid

proc fusionGuest(late: bool = false, wide: bool = false): Program =
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
  if late:
    # A wrapping in-page offset trains with one page but permits a late cross-page fault.
    emit([132'u8, 0x24, 0xff, 0x0f]) # R4 = R2 & 4095.
    emit([200'u8, 0x64, 4]) # R4 = R4 + R6.
    if wide:
      # All13 lanes participate across linked blocks, including full-width aliased writes
      # before the possible paid refusal and a read-only halt sentinel copied into R10.
      emit([149'u8, 0x77, 1])
      emit([149'u8, 0x88, 1])
      emit([100'u8, 0x3a]) # R10 = R3.
      emit([133'u8, 0xbb, 0x80]) # R11 = R11 xor sign-extended -128.
      emit([100'u8, 0xc9]) # R9 = R12 before the later load-and-jump replaces it.
    emit([124'u8, 0x41, 0]) # Read byte R1,[R4].
  else:
    emit([124'u8, 0x61, 0]) # Read byte R1,[R6]. A missing page is a paid fault.
  emit([149'u8, 0x22, 1]) # One completed iteration per pass.
  let second = code.len+7
  jump([80'u8, 0x19, 0x80], second) # Write sign-extended -128 to R9 before the linked target.
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

when NativeReadCycleEnabled:
  proc checkFusionGraphTokens() =
    ## A real255-entry image crosses every receipt byte boundary and reaches token255 on both ISAs.
    ## These literal lowering records test image geometry; only the ordinary public fixtures below
    ## bind execution authority to a Program, gas plan and immutable machine.
    let owner = fusionGuest()
    let original = instruction(owner, CodeAddress(0))
    assert original.error == ProgramError.None
    let slots = instructionRegisters(original)
    var blocks = newSeq[NativeFusionBlock](NativeFusionBlockLimit)
    let outside = NativeEntryLimit-1
    for index in 0..<blocks.len:
      # Each block increments the same full-width lane then follows its unique static successor.
      let header = uint32(index*3)
      blocks[index] = NativeFusionBlock(header: header, terminal: header+2, first: uint32(index*2),
        span: 2, price: 3, targets: [(if index+1 < blocks.len: header+3 else: outside),
          NativeEntryFailure], branch: NativeOperation(opcode: 40))
      blocks[index].operations[0] = NativeOperation(opcode: 149, slots: slots, immediate: 1)
    let image = lowerNativeFusion(blocks)
    assert image.ready and image.codeBytes <= uint64(NativeFusionImageLimit)
    assert nativeFusionEntry(image, NativeFusionBlockLimit-1)
    assert not nativeFusionEntry(image, NativeFusionBlockLimit)
    var memo = default(NativeFusionReceipts)
    for entry in [0, 63, 64, 127, 128, 191, 192, 254]:
      # Entry191 includes token255 as the64th visit; entry254 tests it as the sole visit.
      var registers = default(RegisterFile)
      for slot in 0..12: registers[slot] = RegisterValue(0x1234567800000000'u64+uint64(slot))
      let before = registers
      var context = NativeFusionContext(gas: 10000, remaining: 10000)
      let count = min(NativeFusionVisitLimit, blocks.len-entry)
      let expected = if entry+count == blocks.len: outside else: uint32((entry+count)*3)
      let next = enterNativeFusion(image, entry, registers, context)
      assert next == expected and context.visits == uint64(count) and context.paid == 0
      for slot in 0..12:
        assert uint64(registers[slot]) == uint64(before[slot])+(if slot == 7: uint64(
            count) else: 0'u64)
      let receipt = checkNativeFusionExit(memo, blocks, uint32(entry*3), next, 10000, 10000, context)
      assert receipt.valid and receipt.lastToken == uint32(entry+count)
      assert receipt.attempted == uint32(count*2) and receipt.branches
      assert context.gas == 10000'u64-uint64(count*3)
      assert context.remaining == 10000'u64-uint64(count*2)
      # A proved large-token path never authorizes an internal zero byte on cache reuse.
      let last = count-1
      context.path[last div 8] = context.path[last div 8] and not (255'u64 shl ((last and 7)*8))
      assert not checkNativeFusionExit(memo, blocks, uint32(entry*3), next, 10000, 10000, context).valid
    var idleRegisters = default(RegisterFile)
    var idle = NativeFusionContext(gas: 2, remaining: 10000)
    assert enterNativeFusion(image, NativeFusionBlockLimit-1, idleRegisters, idle) ==
      blocks[NativeFusionBlockLimit-1].header
    assert idle.visits == 0 and idle.gas == 2 and idle.remaining == 10000
    blocks.add(default(NativeFusionBlock))
    assert not lowerNativeFusion(blocks).ready, "a256th graph entry must refuse before publication"

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

proc checkLateFusionFault(wide: bool)
  ## The late paid-memory fixture is defined below the main supported fusion witness.

proc runStaticFusion*() =
  ## Exercise natural selection and exact paid/unpaid exits with changed public inputs.
  checkRepeatedFusionReceipt()
  checkLongFusionReceipts()
  when NativeReadCycleEnabled: checkFusionGraphTokens()
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
  assert uint64(machineInfo(expected.value.machine).value.registers[9]) ==
    cast[uint64](-127'i64), "static load-and-jump reaches the next block with the written value"
  for sample in 0..2:
    # Wait only in the witness, outside invocation, to distinguish queued work from use.
    let outcome = execute(source, limit, jit.value)
    assertSameFusionResult(outcome, expected)
    waitNativeCompiler(runtime)
    let state = preparedInfo(jit.value).value
    if sample == 0: assert state.nativeOperations == 0
    if sample == 1: assert state.nativeOperations < 16 and state.nativeFragments == 2, "training publication"
    if sample == 2:
      # All seven attempts per loop must execute natively, including the load-and-jump terminal.
      assert state.nativeOperations >= 7'u64*90000, "native load-and-jump coverage"

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
  checkLateFusionFault(wide = false)
  checkLateFusionFault(wide = true)

proc checkLateFusionFault(wide: bool) =
  ## A paid read in the 49th linked block must retain all earlier stores and exact accounting.
  let program = fusionGuest(late = true, wide = wide)
  let runtime = newNativeRuntime()
  try:
    assert start(runtime)
  except:
    assert false, "late fusion runtime failed to start"
  let jit = newPreparedProgram(program, defaultPreparedLimits(), PvmBackend.Jit, runtime)
  let checked = newPreparedProgram(program, defaultPreparedLimits(), PvmBackend.Interpreted)
  assert jit.error == PreparationError.None and checked.error == PreparationError.None
  let capturedMemory = captureMemory([PageImage(index: PageIndex(16),
      access: PageAccess.ReadWrite)],
    PageLimit(2))
  assert capturedMemory.error == MachineError.None
  let memory = capturedMemory.value
  var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(8000000))
  info.registers[0] = RegisterValue(165)
  if wide:
    # Nonzero high words expose accidental MOVD truncation of ordinary guest values.
    info.registers[0] = RegisterValue(0xdeadbeef000000a5'u64)
    for slot in [7, 8, 10, 11]:
      info.registers[slot] = RegisterValue(0x1234567800000000'u64+uint64(slot))
  info.registers[3] = RegisterValue(0xffff0000'u64)
  info.registers[5] = RegisterValue(65536)
  info.registers[6] = RegisterValue(65536)
  info.registers[12] = RegisterValue(90000)
  let captured = captureMachine(program, memory, info)
  assert captured.error == MachineError.None
  let source = captured.value
  let limit = ExecutionStepLimit(2000000)
  let expected = execute(source, limit, checked.value)
  assert expected.error == StepError.None and expected.value.exit == StepExit.Halt
  for sample in 0..2:
    # Publish the ordinary seed, then train and collect the same two-block fusion graph.
    assertSameFusionResult(execute(source, limit, jit.value), expected)
    waitNativeCompiler(runtime)
  assert preparedInfo(jit.value).value.nativeFragments == 2
  info.registers[6] = RegisterValue(65536+4096-24)
  let late = captureMachine(program, memory, info)
  assert late.error == MachineError.None
  let before = preparedInfo(jit.value).value.nativeOperations
  let fault = execute(late.value, limit, jit.value)
  assertSameFusionResult(fault, execute(late.value, limit, checked.value))
  assert fault.error == StepError.None and fault.value.exit == StepExit.Fault
  assert preparedInfo(jit.value).value.nativeOperations == before+uint64(2+24*(
      if wide: 14 else: 9)+(if wide: 9 else: 4)),
    "late native progress: " & $(preparedInfo(jit.value).value.nativeOperations-before)
  let cpu = machineInfo(fault.value.machine).value
  assert uint64(cpu.registers[2]) == 24 and cpu.blockCharged, "late counter/paid state"
  assert uint64(fault.value.faultPage) == 17'u64*4096, "late fault page address"
  assert load(memoryOf(fault.value.machine).value, MemoryAddress(65536), AccessWidth(1)).value ==
    RegisterValue(165)
  assert pageImage(memory, PageIndex(16)).value.bytes[0] == 0
  assert machineInfo(late.value).value == info
  assert close(runtime)
