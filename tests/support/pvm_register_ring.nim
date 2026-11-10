# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Direct three-header native entry against independently checked original instructions.

import std/[assertions, syncio]
import ../../src/pvm/[machine, program, step]
import ../../src/pvm/gas/gas
import ../../src/pvm/internal/[native_ir, native_platform, native_register_ring]
when NativeCheckedReadEnabled and defined(pvmSharedAsyncWitness):
  import ../../src/pvm/internal/native_pipeline

const
  # The original ring uses false, false and true respectively to continue.
  Wire = [0'u8, 0, 31, 200, 0x32, 1, 139, 0x11, 4, 82, 8, 21,
    131, 0x44, 1, 88, 0x14, 0xff, 17, 151, 0x55, 1, 152, 0x55, 1, 173, 0x76, 0xea,
    50, 0, 50, 0, 50, 0, 0x49, 0x12, 0x49, 0x2a]
  Headers = [0'u32, 9, 16]
  Yes = [27'u32, 29, 0]
  No = [9'u32, 16, 25]
  Spans = [3'u32, 2, 3]
  First = [0'u32, 3, 5]
  CoordinateBase = 257'u32
  Cycles = GasCycleLimit(1000000)
  Prices: array[3, array[3, uint64]] = [
    [3'u64, 2'u64, 5'u64], [0'u64, 0'u64, 0'u64],
    [0x8000000000000001'u64, 7'u64, 0x100000005'u64]]

proc checkRing() =
  ## Use real decoded operands and compare every register and original continuation.
  let decoded = decodeProgram(Wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  let program = decoded.value
  let memory = captureMemory([], PageLimit(0))
  assert memory.error == MachineError.None
  var cases = 0
  for profile in 0..2:
    let prices = Prices[profile]
    # Publish each price profile through the production direct lowering and image-size check.
    var ring = default(NativeRegisterRing)
    for index in 0..2:
      var item = NativeRingBlock(header: CoordinateBase+Headers[index], first: First[index],
        span: Spans[index], price: prices[index], yes: CoordinateBase+Yes[index],
        no: CoordinateBase+No[index])
      var pc = Headers[index]
      for position in 0..<int(item.span):
        let original = instruction(program, CodeAddress(pc))
        assert original.error == ProgramError.None
        let op = NativeOperation(opcode: original.value.opcode, slots: instructionRegisters(
            original), immediate: uint64(original.value.x))
        if position == int(item.span)-1:
          assert uint32(int64(pc)+int64(original.value.displacement)) == Yes[index]
          assert pc+uint32(original.value.skip)+1 == No[index]
          item.branch = op
        else:
          item.body[position] = op
        pc += uint32(original.value.skip)+1
      ring.blocks[index] = item
    assert ring.complete
    var invalid = ring
    invalid.blocks[1].yes = invalid.blocks[2].header
    assert not lowerNativeRegisterRing(invalid).ready
    let image = lowerNativeRegisterRing(ring)
    assert image.ready and image.codeBytes > 0 and image.codeBytes <= uint64(NativeImageByteLimit)
    for rotation in 0..2:
      for exitAt in 0..3:
        # Each of the three side exits and the no-side-exit case use the same image.
        var initial = default(MachineInfo)
        initial.pc = CodeAddress(Headers[rotation])
        initial.gas = MachineGas(100000)
        for lane in 0..<13:
          initial.registers[lane] = RegisterValue(0x1234567800000100'u64+uint64(lane))
        initial.registers[2] = RegisterValue(high(uint64)-6)
        initial.registers[3] = RegisterValue(12)
        initial.registers[4] = RegisterValue(if exitAt == 1: high(uint64)-1 else: 1'u64)
        initial.registers[6] = RegisterValue(high(uint64))
        initial.registers[7] = RegisterValue(if exitAt == 2: high(uint64)-1 else: 1'u64)
        initial.registers[8] = RegisterValue(uint64(ord(exitAt == 0)))
        for quota in [0'u64, 1, 2, 3, 7, 8, 9, 24]:
          for gas in [0'u64, 2, 9, 31, 0x8000000000000000'u64, high(uint64)]:
            # Use public one-step execution to decide original effects and branch destinations.
            let captured = captureMachine(program, memory.value, initial)
            assert captured.error == MachineError.None
            var expected = captured.value
            var pc = Headers[rotation]
            var role = rotation
            var expectedContext = NativeRingContext(gas: gas, remaining: quota,
              entry: uint64(rotation))
            while pc == Headers[role] and expectedContext.remaining >= uint64(Spans[role]) and
                expectedContext.gas >= prices[role]:
              expectedContext.remaining -= uint64(Spans[role])
              expectedContext.gas -= prices[role]
              inc expectedContext.visits[role]
              for position in 0..<int(Spans[role]):
                let checked = stepOnce(expected, Cycles)
                assert checked.error == StepError.None
                expected = checked.value.machine
              pc = uint32(machineInfo(expected).value.pc)
              role = (role+1) mod 3
            var registers = initial.registers
            var context = NativeRingContext(gas: gas, remaining: quota, entry: uint64(rotation))
            let destination = enterNativeRegisterRing(image, registers, context)
            assert destination == CoordinateBase+pc and context == expectedContext
            assert registers == machineInfo(expected).value.registers
            inc cases
  assert cases == 1728

when NativeCheckedReadEnabled:
  checkRing()
when NativeCheckedReadEnabled and defined(pvmSharedAsyncWitness):
  proc noHost(called: var bool, stop: StepOutcome): HostResponse {.raises: [].} =
    ## The literal ring has no host instructions.
    called = true
    default(HostResponse)

  proc checkRuntimeRing() =
    ## Prove worker selection over the earlier pure prefix and public entry at every rotation.
    let decoded = decodeProgram(Wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
    assert decoded.error == ProgramError.None, "runtime wire"
    let program = decoded.value
    let memory = captureMemory([], PageLimit(0))
    assert memory.error == MachineError.None, "runtime memory"
    let runtime = newNativeRuntime()
    try:
      assert start(runtime)
    except:
      assert false, "register ring worker failed to start"
    let limits = defaultPreparedLimits(Cycles)
    var prepared = default(PreparedProgram)
    block:
      # Drop the constructor result before exercising exclusive image retirement.
      let created = newPreparedProgram(program, limits, PvmBackend.Jit, runtime)
      assert created.error == PreparationError.None
      prepared = created.value
    let checked = newPreparedProgram(program, limits, PvmBackend.Interpreted).value
    let quota = ExecutionStepLimit(20000)
    var called = false
    const gasStart = 10_000_000'u64
    var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(gasStart))
    info.registers[0] = RegisterValue(0xffff0000)
    info.registers[4] = RegisterValue(0x7ffff800)
    info.registers[7] = RegisterValue(1)
    let first = captureMachine(program, memory.value, info).value
    armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
    let trained = executeWithHost(first, called, noHost, quota, HostCallLimit(0), prepared)
    assert not called and trained.error == StepError.None, "training error " & $trained.error
    assert trained.value.exit == StepExit.Halt, "training exit " & $trained.value.exit
    assert trained.value.backend == PvmBackend.Interpreted and runtimeInfo(runtime).submitted == 1,
      "training submission " & $runtimeInfo(runtime).submitted
    let publication = waitNativeCompilerGate(runtime)
    assert publication.hasImage and publication.kind == NativeKind.RegisterRing, "ring selection"
    releaseNativeCompilerGate(runtime)
    waitNativeCompiler(runtime)
    const operations = [16381'u64, 16378'u64, 16384'u64]
    for rotation in 0..2:
      # Reuse the same image with different fresh entry state and compare the full checked result.
      info.pc = CodeAddress(Headers[rotation])
      let source = captureMachine(program, memory.value, info).value
      let baseline = executeWithHost(source, called, noHost, quota, HostCallLimit(0), checked)
      let before = preparedInfo(prepared).value
      let ready = executeWithHost(source, called, noHost, quota, HostCallLimit(0), prepared)
      assert not called and baseline.error == StepError.None and ready.error == StepError.None,
        "ready errors " & $baseline.error & " / " & $ready.error
      assert ready.value.backend == PvmBackend.Jit and ready.value.exit == baseline.value.exit,
        "ready backend and exit at rotation " & $rotation
      assert machineInfo(ready.value.machine).value == machineInfo(baseline.value.machine).value,
        "checked machine parity at rotation " & $rotation
      let after = preparedInfo(prepared).value
      assert after.nativeFragments == 1 and after.nativeCalls == before.nativeCalls+1,
        "one entry at rotation " & $rotation
      assert after.nativeOperations == before.nativeOperations+operations[rotation],
        "complete source work at rotation " & $rotation & ": " &
        $(after.nativeOperations-before.nativeOperations)
    var ringPrice = 0'u64
    for rotation in 0..2:
      # Derive actual original full-header prices through the independent one-step API.
      info.pc = CodeAddress(Headers[rotation])
      let source = captureMachine(program, memory.value, info).value
      let firstStep = stepOnce(source, Cycles)
      assert firstStep.error == StepError.None, "price source step"
      ringPrice += uint64(info.gas)-uint64(machineInfo(firstStep.value.machine).value.gas)
    for quotaLeft in [4097, 4099]:
      # Native whole visits leave checked quota and positive-partial-plus-low-gas precedence intact.
      for gas in [ringPrice*512'u64, gasStart]:
        info.pc = CodeAddress(0)
        info.gas = MachineGas(gas)
        let source = captureMachine(program, memory.value, info).value
        let budget = ExecutionStepLimit(quotaLeft)
        let baseline = executeWithHost(source, called, noHost, budget, HostCallLimit(0), checked)
        let before = preparedInfo(prepared).value
        let ready = executeWithHost(source, called, noHost, budget, HostCallLimit(0), prepared)
        let after = preparedInfo(prepared).value
        assert after.nativeCalls == before.nativeCalls+1, "one guarded native entry"
        assert not called and ready.error == baseline.error, "checked boundary result"
        if baseline.error == StepError.None:
          assert ready.value.exit == baseline.value.exit, "boundary exit parity"
          assert machineInfo(ready.value.machine).value == machineInfo(
              baseline.value.machine).value,
            "boundary machine parity at " & $quotaLeft & " / " & $gas
    prepared = default(PreparedProgram)
    assert close(runtime), "close register ring worker"
    assert runtimeInfo(runtime).registered == 0, "retire register ring image"

proc runRegisterRing*() =
  ## Check direct execution and the prepared-owner path on the selected native host.
  when NativeCheckedReadEnabled:
    checkRing()
    when defined(pvmSharedAsyncWitness):
      checkRuntimeRing()
  echo "PVM native register ring passed"
