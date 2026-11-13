# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Direct three-header native entry against independently checked original instructions.

import std/[assertions, syncio]
import ../../src/pvm/[machine, program, step]
import ../../src/pvm/gas/gas
import ../../src/pvm/internal/[native_ir, native_platform, native_register_ring]
when NativeCheckedReadEnabled and defined(pvmX86Jit) and defined(pvmX86ResidentProof):
  import ../../src/pvm/internal/x86_jit
when NativeCheckedReadEnabled and defined(pvmSharedAsyncWitness):
  import ../../src/pvm/internal/[handler_stream, native_pipeline]

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
  Prices: array[6, array[3, uint64]] = [
    [3'u64, 2, 5], [0'u64, 0, 0], [0'u64, 4095, 0], [4095'u64, 1, 0],
    [0x8000000000000001'u64, 7, 0x100000005'u64], [high(uint64), 1, 2]]

proc ringFixture(wire: openArray[byte], prices: array[3, uint64]): NativeRegisterRing =
  ## Copy the decoded source and original successors for each operand fixture.
  let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  let program = decoded.value
  result = default(NativeRegisterRing)
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
    result.blocks[index] = item
  assert result.complete

proc checkRing(wire: openArray[byte] = Wire, signedRight = 7, addLane = 2,
    addStart = high(uint64)-6, wordStart = 1'u64, profileCount = Prices.len) =
  ## Use real decoded operands and compare every register and original continuation.
  let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  let program = decoded.value
  let memory = captureMemory([], PageLimit(0))
  assert memory.error == MachineError.None
  var cases = 0
  assert profileCount in 1..Prices.len
  for profile in 0..<profileCount:
    let prices = Prices[profile]
    # Publish each price profile through the production direct lowering and image-size check.
    let ring = ringFixture(wire, prices)
    assert ring.complete
    let round = nativeRingRoundBudget(ring)
    assert round.enabled == (profile <= 2)
    if profile == 0:
      assert round.price == 10 and round.suffixPrices == [7'u32, 5]
    elif profile == 2:
      assert round.price == 4095 and round.suffixPrices == [4095'u32, 0]
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
        initial.registers[addLane] = RegisterValue(addStart)
        initial.registers[3] = RegisterValue(12)
        initial.registers[4] = RegisterValue(if exitAt == 1: high(uint64)-1 else: wordStart)
        initial.registers[6] = RegisterValue(high(uint64))
        initial.registers[signedRight] = RegisterValue(if exitAt == 2: high(uint64)-1 else: 1'u64)
        initial.registers[8] = RegisterValue(uint64(ord(exitAt == 0)))
        for quota in [0'u64, 1, 2, 3, 7, 8, 9, 24]:
          for gas in [0'u64, 2, 9, 10, 31, 4094, 4095, 4096,
              0x8000000000000000'u64, high(uint64)]:
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
  assert cases == profileCount*960

when NativeCheckedReadEnabled and defined(pvmSharedAsyncWitness):
  proc noHost(called: var bool, stop: StepOutcome): HostResponse {.raises: [].} =
    ## The literal ring has no host instructions.
    called = true
    default(HostResponse)

  proc runRingFrame(plan: FlatPlan, source: Machine, session: NativeSession,
      stream: var FlatStream, budget: uint64): MachineInfo =
    ## Exercise the normal exclusive stream restore and worker boundary without a host callback.
    beginNativeInvocation(session, budget)
    var created = prepareFlatMemoryFrame(plan, source.memoryOf.value, source.machineInfo.value)
    assert created.error == FlatError.None
    var frame = takeValue(created)
    frame.nativeSession = session
    restoreFlatStream(frame, stream)
    runFlat(frame, budget)
    assert frame.reason == StepError.None and frame.exit == StepExit.Halt
    let work = settledNativeWork(frame, budget)
    stream = takeFlatStream(frame)
    finishNativeInvocation(session, work)
    frame.info

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
    var blocker = default(PreparedProgram)
    block:
      # Drop both constructor results before testing exact image retirement.
      let created = newPreparedProgram(program, limits, PvmBackend.Jit, runtime)
      let occupying = newPreparedProgram(program, limits, PvmBackend.Jit, runtime)
      assert created.error == PreparationError.None and occupying.error == PreparationError.None
      prepared = created.value
      blocker = occupying.value
    let checked = newPreparedProgram(program, limits, PvmBackend.Interpreted).value
    let quota = ExecutionStepLimit(20000)
    var called = false
    const gasStart = 10_000_000'u64
    var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(gasStart))
    info.registers[0] = RegisterValue(0xffff0000)
    info.registers[4] = RegisterValue(0x7ffff800)
    info.registers[7] = RegisterValue(1)
    let first = captureMachine(program, memory.value, info).value
    pauseNativeCompiler(runtime, true)
    let occupying = executeWithHost(first, called, noHost, quota, HostCallLimit(0), blocker)
    assert occupying.error == StepError.None and occupying.value.exit == StepExit.Halt
    assert runtimeInfo(runtime).phase == NativePhase.Queued and runtimeInfo(runtime).submitted == 1
    let trained = executeWithHost(first, called, noHost, quota, HostCallLimit(0), prepared)
    assert not called and trained.error == StepError.None and trained.value.exit == StepExit.Halt
    assert trained.value.backend == PvmBackend.Interpreted and runtimeInfo(runtime).submitted == 1
    assert preparedNativeState(prepared).value == NativeState.Deferred
    pauseNativeCompiler(runtime, false)
    waitNativeCompiler(runtime)
    blocker = default(PreparedProgram)
    assert runtimeInfo(runtime).registered == 0
    armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
    # The retry exits from the first block. This short call cannot observe a new closed round.
    var shortInfo = info
    shortInfo.registers[8] = RegisterValue(1)
    let short = captureMachine(program, memory.value, shortInfo).value
    let retried = executeWithHost(short, called, noHost, ExecutionStepLimit(64), HostCallLimit(0), prepared)
    assert retried.error == StepError.None and retried.value.exit == StepExit.Halt
    assert retried.value.backend == PvmBackend.Interpreted and runtimeInfo(runtime).submitted == 2
    let publication = waitNativeCompilerGate(runtime)
    assert publication.hasImage and publication.kind == NativeKind.RegisterRing, "retained ring retry"
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
    # A ready paid entry must leave the first debit with its original checked worker.
    info.pc = CodeAddress(0)
    info.gas = MachineGas(gasStart)
    info.blockCharged = true
    let paid = captureMachine(program, memory.value, info).value
    let paidExpected = executeWithHost(paid, called, noHost, quota, HostCallLimit(0), checked)
    let beforePaid = preparedInfo(prepared).value
    let paidActual = executeWithHost(paid, called, noHost, quota, HostCallLimit(0), prepared)
    assert paidExpected.error == StepError.None and paidActual.error == StepError.None
    assert paidExpected.value.exit == paidActual.value.exit and not called
    assert machineInfo(paidActual.value.machine).value == machineInfo(
        paidExpected.value.machine).value
    assert preparedInfo(prepared).value.nativeCalls == beforePaid.nativeCalls, "paid entry stays checked"
    prepared = default(PreparedProgram)
    assert runtimeInfo(runtime).registered == 0

    # Cancel an actual old-epoch nomination after the handoff and discard its checked stream.
    var admitted = prepareFlatPlan(program, Cycles, defaultFlatLimits(), allowNative = false)
    assert admitted.error == FlatError.None
    let plan = takeValue(admitted)
    var session = newNativeSession(runtime)
    var stream = default(FlatStream)
    let oldEpoch = nativeEpoch(session)
    let beforeReset = runtimeInfo(runtime)
    pauseNativeCompiler(runtime, true)
    let original = runRingFrame(plan, first, session, stream, uint64(quota))
    assert nativeState(session) == NativeState.Pending
    assert runtimeInfo(runtime).submitted == beforeReset.submitted+1
    invalidateNativeStream(session)
    stream = default(FlatStream)
    assert nativeEpoch(session) == oldEpoch+1 and nativeState(session) == NativeState.Deferred
    pauseNativeCompiler(runtime, false)
    waitNativeCompiler(runtime)
    assert runtimeInfo(runtime).registered == 0 and runtimeInfo(runtime).completed ==
        beforeReset.completed
    armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
    let rebuilt = runRingFrame(plan, first, session, stream, uint64(quota))
    assert original == rebuilt and runtimeInfo(runtime).submitted == beforeReset.submitted+2
    let replacement = waitNativeCompilerGate(runtime)
    assert replacement.kind == NativeKind.RegisterRing and replacement.hasImage
    assert replacement.epoch == oldEpoch+1 and replacement.ticket > publication.ticket
    releaseNativeCompilerGate(runtime)
    waitNativeCompiler(runtime)
    let ready = runRingFrame(plan, first, session, stream, uint64(quota))
    let stats = nativeStatistics(session)
    assert ready == original and stats[0] == 1 and stats[1] == 1 and stats[2] == operations[0]
    session = default(NativeSession)
    assert close(runtime), "close register ring worker"
    assert runtimeInfo(runtime).registered == 0, "retire register ring image"

  when defined(pvmX86Jit):
    proc checkAdjacentRing() =
      ## Train the real asynchronous worker on a literal pair at PCs unrelated to the guest benchmark.
      let wire = [0'u8, 0, 17, 149, 0x33, 1, 200, 0x55, 5, 170, 0x43, 9,
        132, 0x55, 0, 81, 5, 0xf4, 50, 0, 0x49, 0x92, 0]
      let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
      let capturedMemory = captureMemory([], PageLimit(0))
      assert decoded.error == ProgramError.None and capturedMemory.error == MachineError.None, "adjacent fixture"
      let program = decoded.value
      let memory = capturedMemory.value
      let runtime = newNativeRuntime()
      try:
        assert start(runtime)
      except:
        assert false, "adjacent ring worker failed to start"
      let limits = defaultPreparedLimits(Cycles)
      let prepared = newPreparedProgram(program, limits, PvmBackend.Jit, runtime).value
      let checked = newPreparedProgram(program, limits, PvmBackend.Interpreted).value
      var cpu = MachineInfo(pc: CodeAddress(0), gas: MachineGas(10_000_000))
      cpu.registers[4] = RegisterValue(2048)
      let source = captureMachine(program, memory, cpu).value
      var called = false
      pauseNativeCompiler(runtime, true)
      let cold = executeWithHost(source, called, noHost, ExecutionStepLimit(10240),
        HostCallLimit(0), prepared)
      assert cold.error == StepError.None and cold.value.exit == StepExit.Halt and not called, "adjacent cold outcome"
      assert cold.value.backend == PvmBackend.Interpreted, "adjacent cold policy"
      assert runtimeInfo(runtime).phase == NativePhase.Queued and runtimeInfo(runtime).submitted ==
          1, "adjacent queued"
      pauseNativeCompiler(runtime, false)
      waitNativeCompiler(runtime)
      assert runtimeInfo(runtime).completed == 1, "adjacent publication completed"
      for pc in [0'u64, 9]:
        # Two warm entry rotations must visit the real pair exactly once per guest invocation.
        cpu.pc = CodeAddress(pc)
        let fresh = captureMachine(program, memory, cpu).value
        let before = preparedInfo(prepared).value
        let ready = executeWithHost(fresh, called, noHost, ExecutionStepLimit(11000),
          HostCallLimit(0), prepared)
        let baseline = executeWithHost(fresh, called, noHost, ExecutionStepLimit(11000),
          HostCallLimit(0), checked)
        assert ready.error == StepError.None and baseline.error == StepError.None,
            "adjacent ready errors " & $pc & " " & $ready.error & " " & $baseline.error
        assert ready.value.backend == PvmBackend.Jit and ready.value.exit == baseline.value.exit,
            "adjacent ready policy and exit " & $pc
        assert machineInfo(ready.value.machine).value == machineInfo(baseline.value.machine).value,
            "adjacent ready CPU " & $pc
        assert memoryOf(ready.value.machine).value == memoryOf(baseline.value.machine).value, "adjacent ready memory"
        let after = preparedInfo(prepared).value
        assert after.nativeFragments == 1 and after.nativeCalls == before.nativeCalls+1,
            "adjacent ready calls " & $pc & " " & $after.nativeCalls
        assert after.nativeOperations-before.nativeOperations == (if pc ==
            0: 10238'u64 else: 10240'u64),
          "adjacent ready attempts " & $pc & " " & $(after.nativeOperations-before.nativeOperations)
      let firstPrice = uint64(blockGas(program, CodeAddress(0), Cycles).value)
      let secondPrice = uint64(blockGas(program, CodeAddress(9), Cycles).value)
      for pc in [0'u64, 9]:
        # Original paid entry, unsigned gas debits and partial quota stay observable after publication.
        cpu.pc = CodeAddress(pc)
        for paid in [false, true]:
          cpu.blockCharged = paid
          for gas in [0'u64, firstPrice, firstPrice+secondPrice, high(uint64)]:
            cpu.gas = MachineGas(gas)
            let fresh = captureMachine(program, memory, cpu).value
            for quota in [4096, 4097, 4098, 4100]:
              let limit = ExecutionStepLimit(quota)
              let baseline = executeWithHost(fresh, called, noHost, limit, HostCallLimit(0), checked)
              let ready = executeWithHost(fresh, called, noHost, limit, HostCallLimit(0), prepared)
              assert not called and baseline.error == ready.error, "adjacent boundary result " &
                  $pc & " " & $quota & " " & $gas & " " & $paid
              if ready.error == StepError.None:
                assert baseline.value.exit == ready.value.exit, "adjacent boundary exit"
                assert machineInfo(baseline.value.machine).value == machineInfo(
                    ready.value.machine).value
      assert close(runtime)

func sixLaneWire(): array[38, byte] =
  ## Fit six lanes by saturating the ADD/SHR aliases to r12 and reusing r3 in the final branch.
  result = Wire
  result[4] = 0x3f
  result[5] = 0x0f
  result[7] = 0xff
  result[26] = 0x36

when NativeCheckedReadEnabled and defined(pvmX86Jit) and defined(pvmX86ResidentProof):
  proc checkResidentRing() =
    ## Prove selected direct paths and retained capacity/extent fallbacks through the native ABI.
    let six = sixLaneWire()
    var seven = six
    seven[26] = Wire[26]
    let fitted = ringFixture(six, Prices[0])
    let oversized = ringFixture(seven, Prices[0])
    let resident = encodeX86RegisterRing(fitted)
    let canonical = x86CanonicalRingProof(fitted)
    assert resident.len > 0 and resident != canonical and resident.len < NativeImageByteLimit
    assert x86ResidentRingLimitProof(fitted, resident.len+1) == resident
    assert x86ResidentRingLimitProof(fitted, resident.len) == canonical
    assert encodeX86RegisterRing(oversized) == x86CanonicalRingProof(oversized)
    checkRing(six, signedRight = 3, addLane = 12)
    checkRing(seven, addLane = 12)

    # Distinct destinations reuse other mapped lanes. Masked-zero SHR32 must extend a negative word.
    var distinctWire = six
    distinctWire[5] = 5
    distinctWire[7] = 0x5f
    distinctWire[8] = 32
    distinctWire[13] = 0x46
    let distinctRing = ringFixture(distinctWire, Prices[0])
    assert encodeX86RegisterRing(distinctRing) != x86CanonicalRingProof(distinctRing)
    checkRing(distinctWire, signedRight = 3, addLane = 12,
      addStart = 0xfffffff0'u64, wordStart = 0x7fffffff'u64)

    # A destination aliasing B consumes B before writing the sum.
    var rightAlias = six
    rightAlias[5] = 3
    rightAlias[7] = 0x3f
    let aliasRing = ringFixture(rightAlias, Prices[0])
    assert encodeX86RegisterRing(aliasRing) != x86CanonicalRingProof(aliasRing)
    checkRing(rightAlias, signedRight = 3, addLane = 12)

  proc checkResidentAddWordImmediate() =
    ## Cross both signed imm8 bounds on the mapped ADDW path and check the full signed results.
    const edges = [127'i16, 128, -128, -129]
    var lengths = default(array[edges.len, int])
    for index in 0..<edges.len:
      let immediate = edges[index]
      var wire = sixLaneWire()
      # Use two immediate bytes by shortening the following branch's compare operand to zero.
      # Only the branch moves within its block, so the block targets and prices still match.
      let encoded = cast[uint16](immediate)
      wire[14] = byte(encoded and 255)
      wire[15] = byte(encoded shr 8)
      wire[16] = 88
      wire[17] = 4
      wire[18] = 16
      wire[35] = 0x22
      let ring = ringFixture(wire, Prices[0])
      let add = ring.blocks[1].body[0]
      assert (add.immediate and 0xffffffff'u64) == uint64(cast[uint32](int32(immediate)))
      let resident = encodeX86RegisterRing(ring)
      assert resident.len > 0 and resident != x86CanonicalRingProof(ring)
      lengths[index] = resident.len
      let start = if immediate > 0: 0x7fffff81'u64 else: 0x8000007f'u64
      checkRing(wire, signedRight = 3, addLane = 12, wordStart = start, profileCount = 1)
    # Each wider immediate adds three bytes in both the reserved and guarded copies.
    assert lengths[1] == lengths[0]+6 and lengths[3] == lengths[2]+6

when NativeCheckedReadEnabled:
  proc checkRingShiftPairs() =
    ## Run actual reserved and guarded C bodies against original checked steps on both ISAs.
    const counts: array[6, array[2, byte]] = [
      [0'u8, 64], [1'u8, 65], [32'u8, 96], [40'u8, 104], [63'u8, 127], [40'u8, 41]]
    for index in 0..<counts.len:
      var wire = sixLaneWire()
      wire[21] = counts[index][0]
      wire[24] = counts[index][1]
      let body = ringFixture(wire, Prices[0]).blocks[2].body
      assert matchesNativeRingShiftPair(body[0], body[1]) == (index != counts.len-1)
      checkRing(wire, signedRight = 3, addLane = 12, profileCount = 1)

    for kind in 0..2:
      var wire = sixLaneWire()
      wire[21] = 40
      wire[24] = 40
      case kind
      of 0:
        # The first source may differ from the chained destination.
        wire[20] = 0x65
      of 1:
        # A distinct second source prevents consuming the first result.
        wire[23] = 0x65
      else:
        # A distinct second destination leaves the first write observable.
        wire[23] = 0x56
      let body = ringFixture(wire, Prices[0]).blocks[2].body
      assert matchesNativeRingShiftPair(body[0], body[1]) == (kind == 0)
      checkRing(wire, signedRight = 3, addLane = 12, profileCount = 1)

proc runRegisterRing*() =
  ## Check direct execution and the prepared-owner path on the selected native host.
  when NativeCheckedReadEnabled:
    checkRing()
    checkRingShiftPairs()
    when defined(pvmX86Jit) and defined(pvmX86ResidentProof):
      checkResidentRing()
      checkResidentAddWordImmediate()
    when defined(pvmSharedAsyncWitness):
      when defined(pvmX86Jit): checkAdjacentRing()
      checkRuntimeRing()
  echo "PVM native register ring passed"
