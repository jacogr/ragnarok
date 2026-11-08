# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal scalar-read transactions and source-certified public native histories on either ISA.

import std/[assertions, envvars, syncio]
import ../../src/pvm/[machine, program, step]
import ../../src/pvm/gas/gas
import ../../src/pvm/internal/[native_ir, native_pipeline, native_platform, native_read_body]
when NativeCheckedReadEnabled:
  import ../../src/pvm/internal/handler_stream

const
  ReadTrips = 40000'u64
  PrefixTrips = 1400'u64
  GasStart = 3000000'u64
  Budget = ExecutionStepLimit(600000)
  # The independent read block's UNLIKELY latency40 dominates three independent loads
  # and the four optional immediate writes. The counter block and prefix cost3 per visit.
  EndGas = GasStart-3*PrefixTrips-43*ReadTrips-22
  Forms = [125'u8, 126, 127, 128]
  Widths = [1, 2, 2, 4]
  Primary = [0xffffffffffffff80'u64, 0x8080, 0xffffffffffff8080'u64, 0x80018080'u64]
  Changed = [0x11'u64, 0x2211, 0x2211, 0x84332211'u64]
  Repeated = [0xffffffffffffff80'u64, 0x8080, 0xffffffffffff8080'u64, 0x80808080'u64]
  ChainOffsets = [0x10080'u32, 0x7f80, 0x17f80, 0x7f807f80]

proc noHost(called: var bool, stop: StepOutcome): HostResponse {.raises: [].} =
  ## Any callback invalidates these read-only, host-free guest histories.
  called = true
  default(HostResponse)

proc decode(code: openArray[byte], starts: openArray[int]): Program =
  ## Encode only a short literal program and independently supplied instruction-start mask.
  assert code.len > 0 and code.len < 64, "bounded literal program size"
  var wire = @[0'u8, 0, byte(code.len)]
  for value in code: wire.add(value)
  var mask = newSeq[byte]((code.len+7) div 8)
  for pc in starts:
    # Mask membership, rather than the emitter, defines the original operand extent.
    assert pc >= 0 and pc < code.len, "literal instruction start in source"
    mask[pc div 8] = mask[pc div 8] or byte(1 shl (pc mod 8))
  for value in mask: wire.add(value)
  let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert decoded.error == ProgramError.None, "literal read program decoding"
  decoded.value

proc copiedOperation(opcode, lanes: byte, immediate: uint32): NativeOperation =
  ## Obtain genuine operand-slot interpretation for the direct mechanical transaction only.
  let code = [opcode, lanes, byte(immediate and 255), byte((immediate shr 8) and 255),
    byte((immediate shr 16) and 255), byte(immediate shr 24), 0'u8]
  let owner = decode(code, [0, 6])
  let decoded = instruction(owner, CodeAddress(0))
  assert decoded.error == ProgramError.None, "decode genuine mechanical operands"
  NativeOperation(opcode: opcode, slots: instructionRegisters(decoded),
    immediate: uint64(decoded.value.x))

proc transaction(opcode: byte, alias = false, displacement = 0'u32,
    lateNew = false): NativeReadBody =
  ## A real typed native image speculates one increment and two loads before publication.
  result = initNativeReadBody(0, 4, 1, 5, 1)
  assert addReadBodyOperation(result, 1, 2, copiedOperation(149, 0x77, 1)), "stage arithmetic prefix"
  if lateNew:
    # The new form itself must be the late guard refusal, after an earlier staged load.
    assert addReadBodyOperation(result, 2, 3, copiedOperation(124, 0x61, 0)), "stage first valid read"
    assert addReadBodyOperation(result, 3, 4, copiedOperation(opcode, 0x52, displacement)), "stage late new-form read"
  else:
    # Reading the old aliased base precedes replacing it with a full signed/unsigned value.
    assert addReadBodyOperation(result, 2, 3,
      copiedOperation(opcode, if alias: 0x55'u8 else: 0x51'u8, displacement)), "stage first new-form read with exact aliases"
    assert addReadBodyOperation(result, 3, 4,
      copiedOperation(124, if alias: 0x52'u8 else: 0x62'u8, 0)), "stage following current-base read"
  assert result.complete, "complete bounded read transaction"

proc initialRegisters(): RegisterFile =
  ## Nonzero upper bits expose accidentally narrow destination writes and unintended clobbers.
  result = default(RegisterFile)
  for slot in 0..<13: result[slot] = RegisterValue(0x1234567800000000'u64+uint64(slot))
  result[5] = RegisterValue(0x20000)
  result[6] = RegisterValue(0x30000)
  result[7] = RegisterValue(10)

when NativeCheckedReadEnabled:
  proc mechanical(form: int) =
    ## Exercise the shared typed ABI independently of production nomination or public counters.
    assert form >= 0 and form < Forms.len, "known scalar form index"
    let opcode = Forms[form]
    let width = Widths[form]
    var image = lowerNativeReadBody(transaction(opcode))
    assert image.isReadBody, "mechanical image kind"
    let marker = [0x6d'u8]
    for first in [65535'u64, 65536, 0x20001, 0xfffffff8'u64]:
      # Distinguish protected-prefix bytes so an unadjusted clipped pointer cannot pass.
      var bytes = newSeq[byte](9)
      for index in 0..<bytes.len: bytes[index] = 0x80
      if first == 65535: bytes[0] = 0x11
      let original = bytes
      for length in 0..9:
        var region = default(NativeReadRegion)
        if length > 0: region = initNativeReadRegion(first, bytes.toOpenArray(0, length-1))
        var context = [region, initNativeReadRegion(0x30000, marker), default(NativeReadRegion)]
        for address in [first-1, first, first+1, first+uint64(max(0, length-width)),
            first+uint64(max(0, length-width))+1]:
          # This literal byte-interval oracle does not consult emitted instructions/descriptors.
          let accepted = address >= 65536 and address < 0xffffffff'u64 and
            address >= first and address-first <= uint64(length) and
            uint64(width) <= uint64(length)-(address-first) and
            uint64(width) <= 0xffffffff'u64-address
          var actual = initialRegisters()
          actual[5] = RegisterValue(address or 0x100000000'u64)
          var expected = actual
          if accepted:
            expected[1] = RegisterValue(Repeated[form])
            expected[2] = RegisterValue(0x6d)
            expected[7] = RegisterValue(11)
          assert enterNativeReadBody(image, actual, context) == accepted, "mechanical guard admission"
          assert actual == expected, "complete read transaction / protected extent"
          assert bytes == original, "read body does not write borrowed bytes"

    for displacement in [0x30002'u32, 0xffffffff'u32, 4095'u32, 4096'u32]:
      # Positive wrap, negative displacement and both immediate-encoding boundaries reach0x20000.
      var wrapped = lowerNativeReadBody(transaction(opcode, displacement = displacement))
      let bytes = [0x80'u8, 0x80, 0x80, 0x80]
      var context = [initNativeReadRegion(0x20000, bytes),
        initNativeReadRegion(0x30000, marker), default(NativeReadRegion)]
      var actual = initialRegisters()
      actual[5] = RegisterValue(0x100000000'u64+uint64(0x20000'u32-displacement))
      var expected = actual
      expected[1] = RegisterValue(Repeated[form])
      expected[2] = RegisterValue(0x6d)
      expected[7] = RegisterValue(11)
      assert enterNativeReadBody(wrapped, actual, context) and actual == expected, "wrapped address transaction"

    block aliasedChain:
      # A signed full-width loaded value becomes the next address base only modulo2^32.
      var body = transaction(opcode, alias = true)
      var chained = initNativeReadBody(0, 4, 1, 5, 1)
      for index in 0..<body.len:
        var op = body.operation(index)
        if index == 2: op = copiedOperation(124, 0x52, ChainOffsets[form])
        assert addReadBodyOperation(chained, uint32(index+1), uint32(index+2), op), "rebuild contiguous alias transaction"
      var compiled = lowerNativeReadBody(chained)
      let bytes = [0x80'u8, 0x80, 0x80, 0x80]
      var context = [initNativeReadRegion(0x20000, bytes),
        initNativeReadRegion(65536, marker), default(NativeReadRegion)]
      var actual = initialRegisters()
      var expected = actual
      expected[5] = RegisterValue(Repeated[form])
      expected[2] = RegisterValue(0x6d)
      expected[7] = RegisterValue(11)
      assert enterNativeReadBody(compiled, actual, context) and actual == expected, "alias or recovery transaction"

    block lateRefusal:
      # Check all13 caller registers immediately; later checked replay cannot conceal partial publication.
      var compiled = lowerNativeReadBody(transaction(opcode, lateNew = true))
      let bytes = [0x80'u8, 0x80, 0x80, 0x80]
      var context = [default(NativeReadRegion), initNativeReadRegion(0x30000, marker),
        default(NativeReadRegion)]
      if width > 1: context[0] = initNativeReadRegion(0x20000, bytes.toOpenArray(0, width-2))
      var actual = initialRegisters()
      let before = actual
      assert not enterNativeReadBody(compiled, actual, context) and actual == before, "late transaction rollback"
      context[0] = initNativeReadRegion(0x20000, bytes.toOpenArray(0, width-1))
      var expected = before
      expected[1] = RegisterValue(0x6d)
      expected[2] = RegisterValue(Repeated[form])
      expected[7] = RegisterValue(11)
      assert enterNativeReadBody(compiled, actual, context) and actual == expected, "alias or recovery transaction"

proc guest(opcode: byte, stack: bool, host = false): Program =
  ## Preserve the independent original arbitration program, adding four immediate writes for stack mode.
  var code = @[131'u8, 0x77, 3, 131, 0xaa, 1, 171, 0xba, 0xfa, 0xff, 0xff, 0xff,
    2, opcode, 0x53, opcode, 0x52, 130, 0x84]
  var starts = @[0, 3, 6, 12, 13, 15, 17]
  if stack:
    # Four distinct destinations plus the three reads force the existing seven-dirty stack policy.
    for index, slot in [1'u8, 7, 10, 12]:
      starts.add(code.len)
      code.add(51)
      code.add(slot)
      code.add(byte(0x22+index))
  starts.add(code.len)
  code.add(1) # Original checked fallthrough remains outside the native transaction.
  starts.add(code.len)
  code.add(131)
  code.add(0x66)
  code.add(1)
  let branch = code.len
  starts.add(branch)
  code.add(172)
  code.add(0x96)
  let relative = 0'u32-uint32(branch-12)
  for shift in 0..<4: code.add(byte((relative shr (shift*8)) and 255))
  if host:
    # R1 != R12 selects host7; equal flags halt. After continuation a static jump reenters PC12.
    assert not stack, "host fixture retains independent flag registers"
    starts.add(code.len)
    for value in [171'u8, 0xc1, 8, 0, 0, 0]: code.add(value)
  starts.add(code.len)
  code.add(50)
  code.add(0)
  if host:
    # These literal offsets are independent of parser/emitter-computed labels.
    starts.add(code.len)
    code.add(10)
    code.add(7)
    starts.add(code.len)
    for value in [40'u8, 0xe5, 0xff, 0xff, 0xff]: code.add(value)
  assert code.len == (if host: 44 elif stack: 43 else: 31), "literal guest code length"
  result = decode(code, starts)
  for pc in [13'u64, 15]:
    # Bind each per-form proof to both exact decoded new opcodes in the sole admitted read body.
    let op = instruction(result, CodeAddress(pc))
    assert op.error == ProgramError.None and op.value.opcode == opcode, "public fixture contains each claimed new opcode"

proc input(code: Program, changed = false, last = false, width = 1): Machine =
  ## Capture independent nonzero memory and complete register canaries for each immutable invocation.
  var page = PageImage(index: PageIndex(32), access: PageAccess.ReadOnly)
  for index in 0..<4096: page.bytes[index] = byte((index*17+29) and 255)
  let primary = [0x80'u8, 0x80, 1, 0x80, 0x98, 0xba, 0xdc, 0xfe]
  let alternate = [0x11'u8, 0x22, 0x33, 0x84, 0x55, 0x66, 0x77, 0x88]
  for index in 0..<8: page.bytes[index] = (if changed: alternate[index] else: primary[index])
  if last:
    # At this start only the actual load width fits; an eight-byte guard would incorrectly refuse.
    assert width in [1, 2, 4], "literal endpoint width"
    for index in 0..<width: page.bytes[4096-width+index] = primary[index]
  let memory = captureMemory([page], PageLimit(1))
  assert memory.error == MachineError.None, "capture immutable read page"
  var cpu = MachineInfo(pc: CodeAddress(0), gas: MachineGas(GasStart),
    registers: initialRegisters())
  cpu.registers[0] = RegisterValue(0xffff0000)
  cpu.registers[5] = RegisterValue((if last: 0x21000'u64-uint64(width) else: 0x20000'u64) or
    0x100000000'u64)
  cpu.registers[6] = RegisterValue(0)
  cpu.registers[7] = RegisterValue(0)
  cpu.registers[8] = RegisterValue(0x20000)
  cpu.registers[9] = RegisterValue(ReadTrips)
  cpu.registers[10] = RegisterValue(0)
  cpu.registers[11] = RegisterValue(PrefixTrips)
  let captured = captureMachine(code, memory.value, cpu)
  assert captured.error == MachineError.None, "capture literal CPU and source"
  captured.value

proc sameState(actual, expected, source: Machine) =
  ## Compare every CPU field, immutable code identity and complete RAM mapping/bytes/permissions.
  let a = machineInfo(actual).value
  let b = machineInfo(expected).value
  assert uint64(a.pc) == uint64(b.pc) and uint64(a.gas) == uint64(b.gas) and
    uint64(a.gasDeficit) == uint64(b.gasDeficit) and a.blockCharged == b.blockCharged, "complete CPU parity"
  assert a.registers == b.registers, "all13 register parity"
  assert programOf(actual).value == programOf(source).value, "original program identity"
  let original = memoryOf(source).value
  let indices = pageIndices(original).value
  for memory in [memoryOf(actual).value, memoryOf(expected).value]:
    # Read-only execution must retain all captured pages, including inaccessible canary bytes.
    let current = pageIndices(memory).value
    assert current.len == indices.len, "complete mapping count"
    for index in 0..<indices.len:
      assert uint32(current[index]) == uint32(indices[index]), "ordered page identity"
      let wanted = pageImage(original, indices[index]).value
      let observed = pageImage(memory, indices[index]).value
      assert wanted.access == observed.access and wanted.bytes == observed.bytes, "full page bytes and permissions"

proc completeLiteral(done: StepResult, source: Machine, value, wide: uint64, stack: bool,
    extraGas = 0'u64) =
  ## A separate closed-form oracle prevents native and interpreted paths agreeing on a wrong result.
  assert done.error == StepError.None and done.value.exit == StepExit.Halt, "literal public halt"
  let actual = machineInfo(done.value.machine).value
  assert uint64(actual.pc) == 0 and uint64(actual.gas) == EndGas-extraGas and
    uint64(actual.gasDeficit) == 0 and actual.blockCharged, "literal public CPU/gas"
  var expected = machineInfo(source).value.registers
  expected[2] = RegisterValue(value)
  expected[3] = RegisterValue(value)
  expected[4] = RegisterValue(wide)
  expected[6] = RegisterValue(ReadTrips)
  expected[7] = RegisterValue(3*PrefixTrips)
  expected[10] = RegisterValue(PrefixTrips)
  if stack:
    # These four literal immediate writes neither alter the loop counter nor add a load dependency.
    for index, slot in [1, 7, 10, 12]: expected[slot] = RegisterValue(uint64(0x22+index))
  assert actual.registers == expected, "all13 literal register results"
  sameState(done.value.machine, done.value.machine, source)
  assert uint64(machineInfo(source).value.gas) == GasStart, "immutable source gas unchanged"

proc invoke(source: Machine, owner: PreparedProgram, quota = Budget): StepResult =
  ## Real public calls have no compiler waits or host effects inside their boundary.
  var called = false
  result = executeWithHost(source, called, noHost, quota, HostCallLimit(0), owner)
  assert not called, "empty host callback history"

proc publicWidth(form: int, stack: bool): string =
  ## Qualify one genuine source-bound read image and its fresh/reused/changed-memory histories.
  let code = guest(Forms[form], stack)
  let source = input(code)
  let limits = defaultPreparedLimits(GasCycleLimit(1000))
  let checked = newPreparedProgram(code, limits, PvmBackend.Interpreted).value
  let expected = invoke(source, checked)
  completeLiteral(expected, source, Primary[form], 0xfedcba9880018080'u64, stack)
  let runtime = newNativeRuntime()
  let supported = nativePlatformSupported()
  try:
    assert start(runtime) == supported, "real read-width compiler startup"
  except:
    assert false, "read-width worker startup failed"
  var owner = default(PreparedProgram)
  block:
    # Retire the constructor result before final-drop assertions inspect the registration credit.
    let made = newPreparedProgram(code, limits, PvmBackend.Jit, runtime)
    assert made.error == PreparationError.None, "Jit prepared read owner"
    owner = made.value
  if supported: armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
  let training = invoke(source, owner)
  completeLiteral(training, source, Primary[form], 0xfedcba9880018080'u64, stack)
  assert training.value.backend == PvmBackend.Interpreted, "first public call stays checked"
  result = ""
  if supported:
    # A missed nomination fails before waiting. This deterministic barrier is correctness-only.
    assert runtimeInfo(runtime).submitted == 1, "real production read nomination before correctness gate"
    let parked = waitNativeCompilerGate(runtime)
    releaseNativeCompilerGate(runtime)
    assert parked.hasImage and parked.kind == NativeKind.CheckedReadBody, "actual checked-read image kind"
    let before = preparedInfo(owner).value
    let ready = invoke(source, owner)
    completeLiteral(ready, source, Primary[form], 0xfedcba9880018080'u64, stack)
    sameState(ready.value.machine, expected.value.machine, source)
    assert ready.value.backend == PvmBackend.Jit, "ready public call executes native"
    let active = preparedInfo(owner).value
    let operations = if stack: 7'u64 else: 3'u64
    assert active.nativeFragments == 1 and active.nativeCalls-before.nativeCalls == ReadTrips, "exact read-image call attribution"
    assert active.nativeOperations-before.nativeOperations == operations*ReadTrips, "exact source-body operation attribution"
    assert active.nativeBranchCalls == 0 and active.nativeHeaderCalls == 0, "no unrelated native branch or header activity"
    result = "{\"opcode\":" & $Forms[form] & ",\"dirty\":" & $(if stack: 7 else: 3) &
      ",\"kind\":\"CheckedReadBody\",\"calls\":" & $ReadTrips &
      ",\"operations\":" & $(operations*ReadTrips) & "}"
    for changed in [false, true]:
      # The same ready owner consumes current immutable input bytes rather than retained pointers.
      let current = input(code, changed = changed)
      let baseline = invoke(current, checked)
      let reused = invoke(current, owner)
      completeLiteral(reused, current, if changed: Changed[form] else: Primary[form],
        if changed: 0x8877665584332211'u64 else: 0xfedcba9880018080'u64, stack)
      sameState(reused.value.machine, baseline.value.machine, current)
      assert reused.value.backend == PvmBackend.Jit, "reused owner executes current native source"
    let last = input(code, last = true, width = Widths[form])
    let prior = preparedInfo(owner).value
    let ending = invoke(last, owner)
    completeLiteral(ending, last, Primary[form], 0xfedcba9880018080'u64, stack)
    let ended = preparedInfo(owner).value
    assert ended.nativeCalls == prior.nativeCalls+ReadTrips and
      ended.nativeOperations == prior.nativeOperations+operations*ReadTrips, "actual native read accepts exact-width tail"
    let beyond = withRegister(last, RegisterIndex(5),
      RegisterValue(uint64(machineInfo(last).value.registers[5])+1)).value
    let beforeBeyond = preparedInfo(owner).value
    let beyondExpected = invoke(beyond, checked)
    let beyondActual = invoke(beyond, owner)
    assert beyondActual.error == StepError.None and beyondActual.value.exit == StepExit.Fault,
      "new width crossing the last mapped byte faults"
    sameState(beyondActual.value.machine, beyondExpected.value.machine, beyond)
    let beyondCpu = machineInfo(beyondActual.value.machine).value
    assert uint64(beyondCpu.pc) == 13 and uint32(beyondActual.value.faultPage) == 0x21000 and
      uint64(beyondCpu.gas) == GasStart-3*PrefixTrips-40 and beyondCpu.blockCharged,
      "new-width end fault preserves paid block and exact source PC"
    assert uint64(beyondCpu.registers[3]) == uint64(machineInfo(beyond).value.registers[3]) and
      preparedInfo(owner).value.nativeCalls == beforeBeyond.nativeCalls,
      "faulted new-form destination and native commit count unchanged"
    for quota in [0'u64, 4095, 4096, 4204, 4205, 4208, 4209]:
      # The core five-fact body commits at4205; stack's nine original facts require4209.
      let beforeQuota = preparedInfo(owner).value
      let baseline = invoke(source, checked, ExecutionStepLimit(quota))
      let limited = invoke(source, owner, ExecutionStepLimit(quota))
      assert limited.error == StepError.StepLimitExceeded and limited.error == baseline.error, "public quota failure parity"
      let committed = if quota >= (if stack: 4209'u64 else: 4205'u64): 1'u64 else: 0'u64
      let afterQuota = preparedInfo(owner).value
      assert afterQuota.nativeCalls == beforeQuota.nativeCalls+committed and
        afterQuota.nativeOperations == beforeQuota.nativeOperations+operations*committed, "full original reservation required for native commit"
    let missing = withRegister(source, RegisterIndex(8), RegisterValue(0x22000)).value
    let beforeFault = preparedInfo(owner).value
    let baseline = invoke(missing, checked)
    let faulted = invoke(missing, owner)
    assert faulted.error == StepError.None and faulted.value.exit == StepExit.Fault, "precise late read fault"
    sameState(faulted.value.machine, baseline.value.machine, missing)
    let cpu = machineInfo(faulted.value.machine).value
    assert uint64(cpu.pc) == 17 and uint64(cpu.gas) == GasStart-3*PrefixTrips-40 and
      cpu.blockCharged and uint64(cpu.gasDeficit) == 0 and uint32(faulted.value.faultPage) ==
          0x22000, "literal fault PC paid gas and page"
    assert uint64(cpu.registers[2]) == Primary[form] and uint64(cpu.registers[3]) == Primary[form], "checked replay publishes only earlier completed reads"
    assert uint64(cpu.registers[4]) == uint64(machineInfo(source).value.registers[4]), "faulted destination remains untouched"
    assert preparedInfo(owner).value.nativeCalls == beforeFault.nativeCalls, "refused native transaction contributes no committed call"
    let originalPage = pageImage(memoryOf(source).value, PageIndex(32)).value
    var late = PageImage(index: PageIndex(34), access: PageAccess.Inaccessible)
    late.bytes[0] = 0x78
    late.bytes[7] = 0x12
    let deniedMemory = captureMemory([originalPage, late], PageLimit(2))
    assert deniedMemory.error == MachineError.None, "capture inaccessible late mapping"
    let denied = withMemory(missing, deniedMemory.value).value
    let deniedExpected = invoke(denied, checked)
    let deniedActual = invoke(denied, owner)
    assert deniedActual.error == StepError.None and deniedActual.value.exit == StepExit.Fault and
      uint64(machineInfo(deniedActual.value.machine).value.pc) == 17 and
      uint32(deniedActual.value.faultPage) == 0x22000, "late permission fault ordering"
    sameState(deniedActual.value.machine, deniedExpected.value.machine, denied)
    var middle = PageImage(index: PageIndex(33), access: PageAccess.ReadOnly)
    middle.bytes[37] = 0x93
    late.access = PageAccess.ReadOnly
    let repairedMemory = captureMemory([originalPage, middle, late], PageLimit(3))
    assert repairedMemory.error == MachineError.None, "capture repaired contiguous readable mapping"
    let repaired = withMemory(missing, repairedMemory.value).value
    let beforeRepair = preparedInfo(owner).value
    let repairedExpected = invoke(repaired, checked)
    let repairedActual = invoke(repaired, owner)
    completeLiteral(repairedActual, repaired, Primary[form], 0x1200000000000078'u64, stack)
    sameState(repairedActual.value.machine, repairedExpected.value.machine, repaired)
    assert repairedActual.value.backend == PvmBackend.Jit and
      preparedInfo(owner).value.nativeCalls == beforeRepair.nativeCalls+ReadTrips,
      "repaired fresh mapping reuses the same actual native read image"
    let recovery = invoke(source, owner)
    completeLiteral(recovery, source, Primary[form], 0xfedcba9880018080'u64, stack)
    assert recovery.value.backend == PvmBackend.Jit, "same owner recovers native after fault"
  else:
    # Unsupported profiles still exercise the literal checked oracle but cannot emit native proof.
    assert preparedInfo(owner).value.nativeCalls == 0 and runtimeInfo(runtime).submitted == 0, "unsupported host stays checked without job submission"
  owner = default(PreparedProgram)
  assert runtimeInfo(runtime).registered == 0 and close(runtime), "final owner drop returns registration before compiler close"

type ReadHostContext = object
  ## The callback owns the replacement immutable map and retains its old stopped observation.
  replacement: Memory
  checkpoint: Machine
  calls: int

proc replaceReadMemory(context: var ReadHostContext, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## A genuine callback replaces bytes, resets the one-visit counter and clears its own host selector.
  assert stopped.exit == StepExit.Host, "genuine host suspension"
  assert uint32(stopped.hostCall) == 7 and context.calls == 0, "one literal host7 history"
  context.calls = 1
  context.checkpoint = stopped.machine
  let cpu = machineInfo(stopped.machine).value
  var registers = cpu.registers
  registers[1] = RegisterValue(0)
  registers[6] = RegisterValue(0)
  registers[9] = RegisterValue(1)
  HostResponse(action: HostAction.Continue, gas: cpu.gas, registers: registers,
    memory: context.replacement)

proc hostReentry(form: int) =
  ## A retained public read image must rebuild invocation-only descriptors after a real host map replacement.
  let code = guest(Forms[form], false, host = true)
  var source = input(code)
  source = withRegister(source, RegisterIndex(1), RegisterValue(0)).value
  source = withRegister(source, RegisterIndex(12), RegisterValue(0)).value
  let checked = newPreparedProgram(code, defaultPreparedLimits(GasCycleLimit(1000)),
    PvmBackend.Interpreted).value
  let trainingExpected = invoke(source, checked)
  # A separate conditional branch costs20 before the existing sentinel halt.
  completeLiteral(trainingExpected, source, Primary[form], 0xfedcba9880018080'u64, false, 20)
  let runtime = newNativeRuntime()
  try:
    assert start(runtime), "host reentry compiler startup"
  except:
    assert false, "host reentry compiler failed to start"
  var owner = default(PreparedProgram)
  block:
    # Ensure the constructor result cannot retain the registration at the final-drop assertion.
    let made = newPreparedProgram(code, defaultPreparedLimits(GasCycleLimit(1000)), PvmBackend.Jit, runtime)
    assert made.error == PreparationError.None, "host reentry prepared owner"
    owner = made.value
  armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
  let training = invoke(source, owner)
  sameState(training.value.machine, trainingExpected.value.machine, source)
  assert training.value.backend == PvmBackend.Interpreted and runtimeInfo(runtime).submitted == 1,
    "host fixture checked training nomination"
  let parked = waitNativeCompilerGate(runtime)
  releaseNativeCompilerGate(runtime)
  assert parked.hasImage and parked.kind == NativeKind.CheckedReadBody, "host fixture actual read image"
  source = withRegister(source, RegisterIndex(1), RegisterValue(1)).value
  let changed = input(code, changed = true)
  let oldPage = pageImage(memoryOf(source).value, PageIndex(32)).value
  let replacement = memoryOf(changed).value
  var baselineContext = ReadHostContext(replacement: replacement, checkpoint: source, calls: 0)
  var actualContext = ReadHostContext(replacement: replacement, checkpoint: source, calls: 0)
  let baseline = executeWithHost(source, baselineContext, replaceReadMemory, Budget, HostCallLimit(
      1), checked)
  let done = executeWithHost(source, actualContext, replaceReadMemory, Budget, HostCallLimit(1), owner)
  assert baselineContext.calls == 1 and actualContext.calls == 1, "one host map replacement"
  assert baseline.error == StepError.None and done.error == StepError.None and
    done.value.exit == StepExit.Halt and done.value.backend == PvmBackend.Jit, "native host reentry halt"
  sameState(done.value.machine, baseline.value.machine, withMemory(source, replacement).value)
  let cpu = machineInfo(done.value.machine).value
  var registers = machineInfo(source).value.registers
  registers[1] = RegisterValue(0)
  registers[2] = RegisterValue(Changed[form])
  registers[3] = RegisterValue(Changed[form])
  registers[4] = RegisterValue(0x8877665584332211'u64)
  registers[6] = RegisterValue(1)
  registers[7] = RegisterValue(3*PrefixTrips)
  registers[9] = RegisterValue(1)
  registers[10] = RegisterValue(PrefixTrips)
  assert cpu.registers == registers and uint64(cpu.pc) == 0 and cpu.blockCharged and
    uint64(cpu.gasDeficit) == 0, "literal current-memory registers after host reentry"
  let activity = preparedInfo(owner).value
  assert activity.nativeFragments == 1 and activity.nativeCalls == ReadTrips+1 and
    activity.nativeOperations == 3*(ReadTrips+1), "one new native visit after host replacement"
  for snapshot in [source, actualContext.checkpoint, baselineContext.checkpoint]:
    # Neither replacement nor native descriptor reuse may mutate previous immutable observations.
    let page = pageImage(memoryOf(snapshot).value, oldPage.index).value
    assert page.access == oldPage.access and page.bytes == oldPage.bytes, "old host observation unchanged"
  owner = default(PreparedProgram)
  assert runtimeInfo(runtime).registered == 0 and close(runtime), "host reentry owner final drop"

when NativeCheckedReadEnabled:
  proc certificate(code: Program, info: NativeReadBodyInfo, mutation: int): NativeReadBody =
    ## Rebuild the genuine original operands, or change one field of the otherwise complete certificate.
    result = initNativeReadBody(info.header, info.terminal, info.first, info.last,
      info.epoch+(if mutation == 4: 1'u64 else: 0'u64))
    for index, pc in [13'u64, 15, 17]:
      let decoded = instruction(code, CodeAddress(pc))
      assert decoded.error == ProgramError.None, "certificate original instruction"
      var operation = NativeOperation(opcode: decoded.value.opcode,
        slots: instructionRegisters(decoded), immediate: uint64(decoded.value.x))
      if index == 0:
        # Width/sign, destination and immediate are independently bound to the captured source.
        if mutation == 1: operation.opcode = (if operation.opcode == 125: 126'u8 else: 125'u8)
        if mutation == 2: operation.slots = copiedOperation(operation.opcode, 0x51, 0).slots
        if mutation == 3: operation.immediate = 1
      assert addReadBodyOperation(result, info.header+1+uint32(index),
        info.first+1+uint32(index), operation), "certificate contiguous original coordinates"
    assert result.complete, "complete typed read certificate"

  proc frameBoundaries(form: int) =
    ## Keep partial snapshots observable while testing the same ready source/epoch bridge as public calls.
    let code = guest(Forms[form], false)
    let source = input(code)
    let page = pageImage(memoryOf(source).value, PageIndex(32)).value
    var admitted = prepareFlatPlan(code, GasCycleLimit(1000), defaultFlatLimits(), false)
    assert admitted.error == FlatError.None, "boundary source plan"
    let plan = takeValue(admitted)
    let runtime = newNativeRuntime()
    try:
      assert start(runtime), "boundary compiler startup"
    except:
      assert false, "boundary compiler failed to start"
    var session = newNativeSession(runtime)
    block:
      # Only a real production nomination from a full checked halt can reach the compiler gate.
      var training = newFlatFrame(plan, [page], machineInfo(source).value)
      training.nativeSession = session
      beginNativeInvocation(session, uint64(Budget))
      beginReadProbe(training, uint64(Budget))
      runFlat(training, uint64(Budget))
      endReadProbeSegment(training)
      assert training.reason == StepError.None and training.exit == StepExit.Halt,
        "boundary checked training halt"
      recordNativeWork(session, settledNativeWork(training, uint64(Budget)))
      finishReadProbe(training, true)
      let retained = deferredNativeReadInfo(session)
      assert retained.epoch != 0 and validateNativeRead(session, certificate(code, retained, 0)),
        "original source certificate validates"
      for mutation in 1..4:
        # Each otherwise-valid copied body must fail exact validation without revoking a new epoch.
        assert not validateNativeRead(session, certificate(code, retained, mutation)),
          "stale opcode/slot/immediate/epoch rejected"
      assert validateNativeRead(session, certificate(code, retained, 0)),
        "current source restores validation"
      var stream = takeFlatStream(training)
      armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
      finishNativeInvocation(session, observedNativeWork(session))
      assert runtimeInfo(runtime).submitted == 1, "boundary actual read request"
      let parked = waitNativeCompilerGate(runtime)
      releaseNativeCompilerGate(runtime)
      assert parked.hasImage and parked.kind == NativeKind.CheckedReadBody, "boundary real read image"
      beginNativeInvocation(session, uint64(Budget))
      var cpu = machineInfo(source).value
      cpu.pc = CodeAddress(12)
      var frame = newFlatFrame(plan, [page], cpu)
      frame.nativeSession = session
      restoreFlatStream(frame, stream)
      assert nativeReadInfo(session).epoch == retained.epoch, "current source image installed"
      for attempts in 0'u64..5'u64:
        # Header/noop, first read, second read, third read and checked fallthrough each retain an attempt.
        resetFlatFrame(frame, cpu)
        var checked = newFlatFrame(plan, [page], cpu)
        let before = nativeStatistics(session)
        runFlat(checked, attempts)
        runFlat(frame, attempts)
        var expected = cpu.registers
        if attempts >= 2: expected[3] = RegisterValue(Primary[form])
        if attempts >= 3: expected[2] = RegisterValue(Primary[form])
        if attempts >= 4: expected[4] = RegisterValue(0xfedcba9880018080'u64)
        let pcs = [12'u64, 13, 15, 17, 19, 20]
        assert frame.reason == StepError.StepLimitExceeded and frame.exit == StepExit.Continued,
          "partial source quota exit"
        assert uint64(frame.info.pc) == pcs[int(attempts)] and frame.info.registers == expected,
          "literal partial PC and all13 registers"
        assert uint64(frame.info.gas) == GasStart-(if attempts == 0: 0'u64 else: 40'u64) and
          uint64(frame.info.gasDeficit) == 0 and
          frame.info.blockCharged == (attempts > 0 and attempts < 5), "literal partial paid gas"
        assert frame.remaining == 0 and frame.info == checked.info and frame.reason ==
            checked.reason,
          "complete checked partial snapshot"
        let snapshot = pageImage(flatMemorySnapshot(frame), page.index).value
        assert snapshot.access == page.access and snapshot.bytes == page.bytes, "partial immutable RAM"
        let committed = if attempts == 5: 1'u64 else: 0'u64
        let after = nativeStatistics(session)
        assert after[1] == before[1]+committed and after[2] == before[2]+3*committed,
          "only complete original reservation commits native"
      for gas in [39'u64, 40]:
        # Gas admission precedes the body; exact block charge cannot be paid a second time.
        var priced = cpu
        priced.gas = MachineGas(gas)
        resetFlatFrame(frame, priced)
        runFlat(frame, 5)
        if gas == 39:
          assert frame.reason == StepError.None and frame.exit == StepExit.OutOfGas and
            uint64(frame.info.pc) == 12 and uint64(frame.info.gas) == 39 and
            not frame.info.blockCharged and frame.info.registers == priced.registers,
            "unpaid gas refusal leaves the complete CPU unchanged"
        else:
          assert frame.reason == StepError.StepLimitExceeded and uint64(frame.info.pc) == 20 and
            uint64(frame.info.gas) == 0 and not frame.info.blockCharged, "exact read block gas"
      var paid = cpu
      paid.pc = CodeAddress(13)
      paid.blockCharged = true
      paid.gas = MachineGas(0)
      resetFlatFrame(frame, paid)
      let beforePaid = nativeStatistics(session)
      runFlat(frame, 1)
      var paidRegisters = paid.registers
      paidRegisters[3] = RegisterValue(Primary[form])
      assert frame.reason == StepError.StepLimitExceeded and uint64(frame.info.pc) == 15 and
        frame.info.registers == paidRegisters and uint64(frame.info.gas) == 0 and
        frame.info.blockCharged and nativeStatistics(session)[1] == beforePaid[1],
        "paid interior replay preserves zero gas and one exact attempt"
      let epoch = nativeEpoch(session)
      invalidateNativeStream(session)
      assert nativeEpoch(session) == epoch+1, "destructive source epoch advances"
      resetFlatFrame(frame, cpu)
      let beforeStale = nativeStatistics(session)
      runFlat(frame, 5)
      assert frame.reason == StepError.StepLimitExceeded and uint64(frame.info.pc) == 20 and
        uint64(frame.info.registers[3]) == Primary[form] and
        nativeStatistics(session)[1] == beforeStale[1], "old installed bridge replays checked after epoch change"
      finishNativeInvocation(session, 0)
    session = default(NativeSession)
    assert runtimeInfo(runtime).registered == 0 and close(runtime), "boundary owner final drop"

proc runSharedReadWidths*() =
  ## Both registered ISA profiles share the same literal/public proof and immutable input contract.
  var rows = ""
  for form in 0..<Forms.len:
    when NativeCheckedReadEnabled:
      if nativePlatformSupported():
        mechanical(form)
        frameBoundaries(form)
        hostReentry(form)
    for stack in [false, true]:
      let row = publicWidth(form, stack)
      if row.len > 0:
        if rows.len > 0: rows.add(",")
        rows.add(row)
  let directory = getEnv("RAGNAROK_TEST_EVIDENCE")
  if nativePlatformSupported() and directory.len > 0:
    # Only all eight successful actual-native histories can publish this qualification proof.
    let isa = when defined(pvmX86Jit): "x86_64" else: "arm64"
    try:
      writeFile(directory & "/pvm_read_widths_" & isa & ".json",
        "{\"schema\":1,\"isa\":\"" & isa & "\",\"rows\":[" & rows & "]}\n")
    except:
      assert false, "read-width proof write failed"
  echo "PVM shared scalar read widths passed"
