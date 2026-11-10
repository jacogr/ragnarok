# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual-width absolute loads, transactional native refusals and public async execution.

import std/[assertions, syncio]
import ../../src/pvm/[machine, program, step]
import ../../src/pvm/gas/gas
import ../../src/pvm/internal/[native_ir, native_pipeline, native_platform, native_read_body]

const
  FirstAbsolute = 52'u8
  Widths = [1, 1, 2, 2, 4, 4, 8]
  Trips = 40000'u64
  PrefixTrips = 1400'u64
  StartGas = 3000000'u64
  HaltAttempts = 3*PrefixTrips+7*Trips+1
  Budget = ExecutionStepLimit(600000)
  ForcedPublication = defined(pvmArm64JitRefuse) or defined(pvmX86JitRefuse)

proc decode(code: openArray[byte], starts: openArray[int]): Program =
  ## Supply the complete literal source mask independently of the native certificate.
  assert code.len in 1..64
  var wire = @[0'u8, 0, byte(code.len)]
  for value in code: wire.add(value)
  let maskStart = wire.len
  wire.setLen(maskStart+(code.len+7) div 8)
  for pc in starts:
    assert pc >= 0 and pc < code.len
    let index = maskStart+pc div 8
    wire[index] = wire[index] or byte(1 shl (pc mod 8))
  let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  decoded.value

proc registers(): RegisterFile =
  ## Nonzero, distinct upper and lower bits reveal a spurious base read or narrow register write.
  result = default(RegisterFile)
  for slot in 0..<13:
    result[slot] = RegisterValue(0x1122334455667700'u64+uint64(slot))

func loadValue(bytes: openArray[byte], offset, width: int, signed: bool): uint64 =
  ## Independent little-endian width/sign oracle for the literal initialized bytes.
  assert offset >= 0 and width in [1, 2, 4, 8] and offset <= bytes.len-width
  result = 0
  for index in 0..<width:
    result = result or (uint64(bytes[offset+index]) shl (8*index))
  if signed and width < 8 and bytes[offset+width-1] >= 128:
    result = result or (high(uint64) shl (8*width))

when NativeCheckedReadEnabled:
  proc copied(code: openArray[byte]): NativeOperation =
    ## Extract genuine slots and immediate from one literal operation followed by a trap.
    let owner = decode(code, [0, code.len-1])
    let op = instruction(owner, CodeAddress(0))
    assert op.error == ProgramError.None
    NativeOperation(opcode: op.value.opcode, slots: instructionRegisters(op),
      immediate: uint64(op.value.x))

  proc absoluteOperation(opcode: byte, address: uint64): NativeOperation =
    ## Preserve all four encoded bytes, including the unsigned address's high bit.
    assert address <= 0xffffffff'u64
    copied([opcode, 2'u8, byte(address and 255), byte((address shr 8) and 255),
      byte((address shr 16) and 255), byte(address shr 24), 0'u8])

  proc mechanical(opcode: byte, width: int, signed: bool, stack: bool) =
    ## Enter real shared images across both protected fences and both exact extent boundaries.
    let lowBase = 65530'u64
    let highBase = 0xfffffff0'u64
    let highEnd = 0xffffffff'u64
    let exactHigh = highEnd-uint64(width)
    let exactLow = lowBase+16-uint64(width)
    var low = default(array[16, byte])
    var top = default(array[16, byte])
    for index in 0..<low.len:
      low[index] = byte(0x80+index)
      top[index] = byte(0xa0+index)
    let originalLow = low
    let originalTop = top
    let marker = [0x6d'u8]
    let addresses = [65535'u64, 65536'u64, 0xfffffff7'u64, 0xfffffff8'u64,
      exactLow, exactLow+1, exactHigh, exactHigh+1]
    for address in addresses:
      let operations = if stack: 7'u32 else: 6'u32
      let terminal = operations+1
      var body = initNativeReadBody(0, terminal, 1, terminal+1, 1)
      # A late absolute miss must discard the preceding increment and successful relative load.
      assert addReadBodyOperation(body, 1, 2, copied([149'u8, 0x11, 1, 0]))
      assert addReadBodyOperation(body, 2, 3, copied([124'u8, 0x84, 0]))
      # Six distinct destinations fill the x86 bank. The absent base slot zero is outside it.
      for index, slot in [7'u8, 9, 12]:
        let node = uint32(index)+3
        assert addReadBodyOperation(body, node, node+1, copied([51'u8, slot, 0x35, 0]))
      if stack:
        # A seventh write to slot zero forces the x86 stack policy.
        assert addReadBodyOperation(body, 6, 7, copied([51'u8, 0, 0x35, 0]))
      let absolute = absoluteOperation(opcode, address)
      assert absolute.slots.aIndex == 2 and absolute.slots.bIndex == 0 and
        uint32(absolute.immediate) == uint32(address)
      assert addReadBodyOperation(body, operations, terminal, absolute) and body.complete
      var image = lowerNativeReadBody(body)
      assert image.isReadBody and image.codeBytes > 0, "published typed image for each boundary"
      var context = [initNativeReadRegion(lowBase, low), initNativeReadRegion(highBase, top),
        initNativeReadRegion(0x30000, marker)]
      var actual = registers()
      actual[8] = RegisterValue(0x30000)
      var expected = actual
      let highAddress = address >= highBase
      let base = if highAddress: highBase else: lowBase
      let first = if highAddress: highBase else: 65536'u64
      let ending = if highAddress: highEnd else: lowBase+uint64(low.len)
      let accepted = address >= first and address < ending and uint64(width) <= ending-address
      if accepted:
        let offset = int(address-base)
        let value = if highAddress: loadValue(top, offset, width, signed)
          else: loadValue(low, offset, width, signed)
        expected[1] = RegisterValue(uint64(expected[1])+1)
        expected[2] = RegisterValue(value)
        expected[4] = RegisterValue(0x6d)
        for slot in [7, 9, 12]: expected[slot] = RegisterValue(0x35)
        if stack: expected[0] = RegisterValue(0x35)
      assert enterNativeReadBody(image, actual, context) == accepted, "entered exact-width guard"
      assert actual == expected, "complete register commit or rollback"
      assert low == originalLow and top == originalTop, "borrowed input bytes remain immutable"

proc guest(opcode: byte): Program =
  ## The first loop crosses the invocation floor; the read body ends at a checked fallthrough.
  let code = [131'u8, 0x77, 3, 131, 0xaa, 1, 171, 0xba, 0xfa, 0xff, 0xff, 0xff,
    2, 149, 0x11, 1, 124, 0x84, opcode, 2, 0, 0, 2, 1,
    131, 0x66, 1, 172, 0x96, 0xf1, 0xff, 0xff, 0xff, 50, 0]
  result = decode(code, [0, 3, 6, 12, 13, 16, 18, 23, 24, 27, 33])
  let direct = instruction(result, CodeAddress(18))
  assert direct.error == ProgramError.None and direct.value.opcode == opcode and
    uint64(direct.value.x) == 0x20000'u64 and instructionRegisters(direct).aIndex == 2,
    "public source binds the exact original absolute operand"

proc parity(actual, checked: StepResult, source: Machine) =
  ## Compare complete CPU, exit and all immutable page contents on every observable result.
  assert actual.error == checked.error, "checked error parity"
  if actual.error != StepError.None: return
  assert actual.value.exit == checked.value.exit, "checked exit parity"
  if actual.value.exit == StepExit.Fault:
    assert actual.value.faultPage == checked.value.faultPage, "checked fault page parity"
  let a = actual.value.machine
  let b = checked.value.machine
  assert machineInfo(a).value == machineInfo(b).value, "full checked CPU and gas parity"
  assert programOf(a).value == programOf(source).value, "immutable source program identity"
  let original = memoryOf(source).value
  let wanted = pageIndices(original).value
  for machine in [a, b]:
    let memory = memoryOf(machine).value
    let indices = pageIndices(memory).value
    assert indices.len == wanted.len, "complete checked memory mapping"
    for index in 0..<indices.len:
      assert indices[index] == wanted[index], "checked memory page index"
      let page = pageImage(memory, indices[index]).value
      let expected = pageImage(original, wanted[index]).value
      assert page.bytes == expected.bytes and page.access == expected.access, "checked page parity"

proc input(code: Program, pages: openArray[PageImage], cpu: MachineInfo): Machine =
  ## Each public invocation owns a fresh immutable snapshot.
  let memory = captureMemory(pages, PageLimit(2))
  assert memory.error == MachineError.None
  let source = captureMachine(code, memory.value, cpu)
  assert source.error == MachineError.None
  source.value

proc noHost(called: var bool, stop: StepOutcome): HostResponse {.raises: [].} =
  ## The public nomination path permits a callback, but these literal guests must never call it.
  called = true
  default(HostResponse)

proc invoke(source: Machine, owner: PreparedProgram, quota = Budget): StepResult =
  ## Exercise the public prepared path that observes and submits checked read candidates.
  var called = false
  result = executeWithHost(source, called, noHost, quota, HostCallLimit(0), owner)
  assert not called, "empty host callback history"

proc publicAbsolute(opcode: byte, width: int, signed: bool) =
  ## Join the exact original opcode to an asynchronously published shared leaf and checked replay.
  let code = guest(opcode)
  var target = PageImage(index: PageIndex(32), access: PageAccess.ReadOnly)
  for index in 0..<8: target.bytes[index] = byte(0x80+index)
  # One contiguous RO allocation lets the shared ABI reach both reads. Removing its first page
  # keeps the relative marker valid while the later absolute read faults on checked replay.
  var marker = PageImage(index: PageIndex(33), access: PageAccess.ReadOnly)
  marker.bytes[0] = 0x6d
  var cpu = MachineInfo(pc: CodeAddress(0), gas: MachineGas(StartGas), registers: registers())
  cpu.registers[0] = RegisterValue(0xffff0000)
  cpu.registers[6] = RegisterValue(0)
  cpu.registers[8] = RegisterValue(0x21000)
  cpu.registers[9] = RegisterValue(Trips)
  cpu.registers[10] = RegisterValue(0)
  cpu.registers[11] = RegisterValue(PrefixTrips)
  let source = input(code, [target, marker], cpu)
  let limits = defaultPreparedLimits(GasCycleLimit(1000))
  let interpreted = newPreparedProgram(code, limits, PvmBackend.Interpreted)
  assert interpreted.error == PreparationError.None
  let checked = interpreted.value
  let expected = invoke(source, checked, ExecutionStepLimit(HaltAttempts))
  assert expected.error == StepError.None and expected.value.exit == StepExit.Halt
  assert invoke(source, checked, ExecutionStepLimit(HaltAttempts-1)).error ==
    StepError.StepLimitExceeded, "halt requires the final original attempt"
  let endCpu = machineInfo(expected.value.machine).value
  # The unlikely prefix prices the read body at40, the counter at3 and the halt at22.
  assert uint64(endCpu.gas) == StartGas-3*PrefixTrips-43*Trips-22, "literal terminal gas"
  assert endCpu.registers[2] == RegisterValue(loadValue(target.bytes, 0, width, signed)) and
    endCpu.registers[4] == RegisterValue(0x6d) and endCpu.registers[6] == RegisterValue(Trips),
    "independent literal load and trip count"

  let runtime = newNativeRuntime()
  let supported = nativePlatformSupported()
  try:
    assert start(runtime) == supported, "worker capability"
  except:
    assert false, "absolute-read worker start failed"
  var owner = default(PreparedProgram)
  block:
    let prepared = newPreparedProgram(code, limits, PvmBackend.Jit, runtime)
    assert prepared.error == PreparationError.None
    owner = prepared.value
  if supported: armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
  let training = invoke(source, owner)
  parity(training, expected, source)
  assert training.value.backend == PvmBackend.Interpreted, "first invocation stays checked"
  if supported:
    # A missing nomination fails before waiting at the deterministic worker checkpoint.
    assert runtimeInfo(runtime).submitted == 1, "exact shared absolute-load nomination"
    let published = waitNativeCompilerGate(runtime)
    releaseNativeCompilerGate(runtime)
    assert published.kind == NativeKind.CheckedReadBody and
      published.hasImage == not ForcedPublication, "absolute-load completion kind and publication"
    assert runtimeInfo(runtime).completed == 1, "one worker completion"
  let before = preparedInfo(owner).value
  let ready = invoke(source, owner, ExecutionStepLimit(HaltAttempts))
  parity(ready, expected, source)
  let after = preparedInfo(owner).value
  if supported and not ForcedPublication:
    assert ready.value.backend == PvmBackend.Jit and after.nativeFragments == 1,
      "real shared execution"
    assert after.nativeCalls-before.nativeCalls == Trips and
      after.nativeOperations-before.nativeOperations == 3*Trips,
      "exact original body operations with actual shared calls"
  else:
    assert ready.value.backend == PvmBackend.Interpreted and after.nativeFragments == 0 and
      after.nativeCalls == 0 and after.nativeOperations == 0, "checked empty-publication fallback"
    if supported:
      assert preparedNativeState(owner).value == NativeState.Unavailable,
        "real empty completion permanently retires this nomination"

  for attempts in 0'u64..5'u64:
    # Each quota cuts one original fact position around the first five-fact read reservation.
    let quota = ExecutionStepLimit(3*PrefixTrips+attempts)
    let beforeQuota = preparedInfo(owner).value
    let limited = invoke(source, owner, quota)
    assert limited.error == StepError.StepLimitExceeded, "source quota " & $attempts
    parity(limited, invoke(source, checked, quota), source)
    let commits = if supported and not ForcedPublication and attempts == 5: 1'u64 else: 0'u64
    let afterQuota = preparedInfo(owner).value
    assert afterQuota.nativeCalls == beforeQuota.nativeCalls+commits and
      afterQuota.nativeOperations == beforeQuota.nativeOperations+3*commits,
      "native commits require the full original attempt reservation at quota " & $attempts

  for available in [39'u64, 40'u64]:
    # One less than the read price stops before the body. Exact payment reaches the counter header.
    var priced = cpu
    priced.gas = MachineGas(3*PrefixTrips+available)
    let bounded = input(code, [target, marker], priced)
    let beforePrice = preparedInfo(owner).value
    let stopped = invoke(bounded, owner)
    parity(stopped, invoke(bounded, checked), bounded)
    assert stopped.error == StepError.None and stopped.value.exit == StepExit.OutOfGas
    let stopCpu = machineInfo(stopped.value.machine).value
    let paid = available == 40
    assert stopCpu.pc == CodeAddress(if paid: 24 else: 12) and
      uint64(stopCpu.gas) == (if paid: 0'u64 else: available) and not stopCpu.blockCharged,
      "exact unsigned gas and next original header"
    let commits = if supported and not ForcedPublication and paid: 1'u64 else: 0'u64
    let afterPrice = preparedInfo(owner).value
    assert afterPrice.nativeCalls == beforePrice.nativeCalls+commits and
      afterPrice.nativeOperations == beforePrice.nativeOperations+3*commits

  let missing = input(code, [marker], cpu)
  let beforeFault = preparedInfo(owner).value
  let fault = invoke(missing, owner)
  parity(fault, invoke(missing, checked), missing)
  assert fault.error == StepError.None and fault.value.exit == StepExit.Fault, "late absolute fault"
  let faultCpu = machineInfo(fault.value.machine).value
  assert faultCpu.pc == CodeAddress(18) and faultCpu.blockCharged and
    uint64(faultCpu.gas) == StartGas-3*PrefixTrips-40 and
    faultCpu.registers[1] == RegisterValue(uint64(cpu.registers[1])+1) and
    faultCpu.registers[4] == RegisterValue(0x6d) and faultCpu.registers[2] == cpu.registers[2],
    "late refusal replays only the original already-paid body through its exact fault"
  let afterFault = preparedInfo(owner).value
  assert afterFault.nativeCalls == beforeFault.nativeCalls and
    afterFault.nativeOperations == beforeFault.nativeOperations,
    "late refusal commits no native work"
  assert runtimeInfo(runtime).submitted == (if supported: 1'u64 else: 0'u64),
    "partial and refused calls do not retry publication"
  owner = default(PreparedProgram)
  assert runtimeInfo(runtime).registered == 0 and close(runtime),
    "worker joins after final owner drop"

proc runSharedAbsoluteReads*() =
  ## Run the same literal matrix and public async histories under each supported ISA profile.
  for form in 0..<Widths.len:
    let opcode = FirstAbsolute+byte(form)
    let signed = form in [1, 3, 5]
    when NativeCheckedReadEnabled:
      if nativePlatformSupported() and not ForcedPublication:
        for stack in [false, true]: mechanical(opcode, Widths[form], signed, stack)
    publicAbsolute(opcode, Widths[form], signed)
  echo "PVM shared absolute reads passed"
