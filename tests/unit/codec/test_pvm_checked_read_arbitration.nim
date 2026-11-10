# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Same-owner loop/read arbitration and checked successor reservation boundaries.

import std/[assertions, envvars, syncio]
import ../../../src/pvm/[machine, program, step]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/internal/[native_pipeline, native_platform]
when NativeCheckedReadEnabled:
  import ../../../src/pvm/internal/handler_stream

const
  LoopTrips = 1400'u64
  ReadTrips = 40000'u64
  GasStart = 3000000'u64
  # Both unsigned branches have UNLIKELY successors and cost one pipeline cycle.
  # The prefix and counter blocks each charge 3. The independent-read block charges 40.
  EndGas = GasStart-3*LoopTrips-43*ReadTrips-22
  Quota = ExecutionStepLimit(300000)
  # PC0 and PC3 ADD_IMM_32, PC6 BRANCH_LT_U to PC0, then PC12 begins the read block.
  # PC12..19 UNLIKELY, U8, S32, U64, FALLTHROUGH. U64 uses its own base in R8.
  # PC20 increments R6 and PC23 loops to PC12.
  # PC29 JUMP_IND R0,0 halts. Offset nine in the wire is exactly the prefix branch opcode.
  Wire = [0'u8, 0, 31, 131, 0x77, 3, 131, 0xaa, 1, 172, 0xba, 0xfa, 0xff, 0xff, 0xff,
    2, 124, 0x53, 129, 0x52, 130, 0x84, 1, 131, 0x66, 1, 172, 0x96, 0xf5, 0xff, 0xff, 0xff,
    50, 0, 0x49, 0xb0, 0x9a, 0x20]

proc noHost(called: var bool, stop: StepOutcome): HostResponse {.raises: [].} =
  ## Neither literal program can suspend. The driver asserts the callback remains unused.
  called = true
  default(HostResponse)

proc verifyOutcome(done: StepResult, source: Machine, original: PageImage) =
  ## Both branch forms take the same prefix visits and the same 40,000 read visits.
  assert done.error == StepError.None and done.value.exit == StepExit.Halt
  let initial = machineInfo(source).value
  let actual = machineInfo(done.value.machine).value
  assert uint64(actual.pc) == 0 and actual.blockCharged and uint64(actual.gasDeficit) == 0
  assert uint64(actual.gas) == EndGas
  assert uint64(initial.pc) == 0 and not initial.blockCharged and uint64(initial.gas) == GasStart
  var expected = initial.registers
  expected[2] = RegisterValue(0x76543210)
  expected[3] = RegisterValue(0x10)
  expected[4] = RegisterValue(0xfedcba9876543210'u64)
  expected[6] = RegisterValue(ReadTrips)
  expected[7] = RegisterValue(3*LoopTrips)
  expected[10] = RegisterValue(LoopTrips)
  for i in 0..<13:
    # Validate every register against the independent literal and unchanged-input table.
    assert uint64(actual.registers[i]) == uint64(expected[i])
  assert uint64(initial.registers[6]) == 0 and uint64(initial.registers[7]) == 0
  assert uint64(initial.registers[10]) == 0
  for memory in [memoryOf(source).value, memoryOf(done.value.machine).value]:
    # No admitted instruction mutates the source memory or its read-only capability.
    let indices = pageIndices(memory)
    assert indices.error == MachineError.None and indices.value.len == 1
    assert uint32(indices.value[0]) == uint32(original.index)
    let actualPage = pageImage(memory, original.index)
    assert actualPage.error == MachineError.None and actualPage.value.access == original.access
    assert actualPage.value.bytes == original.bytes

when defined(pvmX86Jit):
  proc verifyReadyReadFallback(code: Program, prepared, checked: PreparedProgram,
      initial: MachineInfo, pages: openArray[PageImage], expectedExit: StepExit) =
    ## Keep the first two reads valid and force the third outside the native extent table.
    var input = initial
    input.registers[8] = RegisterValue(0x22000)
    let memory = captureMemory(pages, PageLimit(2))
    assert memory.error == MachineError.None
    let captured = captureMachine(code, memory.value, input)
    assert captured.error == MachineError.None
    var called = false
    let before = preparedInfo(prepared).value
    assert before.nativeFragments == 1
    let baseline = executeWithHost(captured.value, called, noHost, Quota, HostCallLimit(0), checked)
    let fallback = executeWithHost(captured.value, called, noHost, Quota, HostCallLimit(0),
      prepared)
    assert not called and baseline.error == StepError.None and fallback.error == StepError.None
    let wanted = baseline.value
    let actual = fallback.value
    assert wanted.exit == expectedExit and actual.exit == expectedExit
    assert actual.backend == PvmBackend.Interpreted
    let expectedCpu = machineInfo(wanted.machine).value
    let actualCpu = machineInfo(actual.machine).value
    assert uint64(actualCpu.pc) == uint64(expectedCpu.pc)
    assert uint64(actualCpu.gas) == uint64(expectedCpu.gas)
    assert uint64(actualCpu.gasDeficit) == uint64(expectedCpu.gasDeficit)
    assert actualCpu.blockCharged == expectedCpu.blockCharged
    for slot in 0..<13:
      # The checked replay owns the earlier read results and all remaining guest state.
      assert uint64(actualCpu.registers[slot]) == uint64(expectedCpu.registers[slot])
    assert uint64(actualCpu.registers[2]) == 0x76543210 and uint64(actualCpu.registers[3]) == 0x10
    if actual.exit == StepExit.Fault and wanted.exit == StepExit.Fault:
      # Both permission faults keep the final destination and identify the exact read and page.
      assert uint32(actual.faultPage) == 0x22000 and uint32(wanted.faultPage) == 0x22000
      assert uint64(actualCpu.pc) == 17
      assert uint64(actualCpu.registers[4]) == uint64(initial.registers[4])
    else:
      # Checked replay can complete the read from the extra, noncontiguous readable extent.
      assert uint64(actualCpu.registers[4]) == 0x1200000000000078'u64
    for snapshot in [memory.value, memoryOf(wanted.machine).value, memoryOf(actual.machine).value]:
      # Compare the complete mapping, including retained inaccessible bytes and permissions.
      let indices = pageIndices(snapshot)
      assert indices.error == MachineError.None and indices.value.len == pages.len
      for i, original in pages:
        assert uint32(indices.value[i]) == uint32(original.index)
        let page = pageImage(snapshot, original.index)
        assert page.error == MachineError.None
        assert page.value.access == original.access and page.value.bytes == original.bytes
    let after = preparedInfo(prepared).value
    assert after.nativeFragments == before.nativeFragments
    assert after.nativeCalls == before.nativeCalls
    assert after.nativeOperations == before.nativeOperations

for closed in [true, false]:
  # Only the prefix branch kind changes. BRANCH_NE_U remains equivalent over the fixed monotone counter.
  var wire = Wire
  if not closed:
    wire[9] = 171
  let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  let code = decoded.value
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(0xffff0000)
  registers[5] = RegisterValue(0x20000)
  registers[8] = RegisterValue(0x20000)
  registers[9] = RegisterValue(ReadTrips)
  registers[11] = RegisterValue(LoopTrips)
  var page = PageImage(index: PageIndex(32), access: PageAccess.ReadOnly)
  for i, byteValue in [0x10'u8, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe]:
    # Keep literal source bytes in the read extent and verify the entire page.
    page.bytes[i] = byteValue
  let memory = captureMemory([page], PageLimit(1))
  assert memory.error == MachineError.None
  let source = captureMachine(code, memory.value, MachineInfo(pc: CodeAddress(0),
    gas: MachineGas(GasStart), registers: registers)).value
  let runtime = newNativeRuntime()
  let supported = nativePlatformSupported()
  try:
    let started = start(runtime)
    assert started == supported
  except:
    assert false, "read arbitration worker failed to start"
  var prepared = default(PreparedProgram)
  block:
    let created = newPreparedProgram(code, defaultPreparedLimits(GasCycleLimit(1000)),
      PvmBackend.Jit, runtime)
    assert created.error == PreparationError.None
    prepared = created.value
  var called = false
  if supported:
    # Park only a real worker so the first call stays checked on both profiles.
    armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
  let trained = executeWithHost(source, called, noHost, Quota, HostCallLimit(0), prepared)
  verifyOutcome(trained, source, page)
  assert not called and trained.value.backend == PvmBackend.Interpreted
  if not supported:
    # Both branch forms ran the full checked oracle without a worker or native image.
    let worker = runtimeInfo(runtime)
    let owner = preparedInfo(prepared).value
    assert worker.submitted == 0 and worker.completed == 0 and worker.completions == 0
    assert worker.registered == 0 and worker.active == 0
    assert owner.nativeFragments == 0 and owner.nativeCalls == 0 and owner.nativeOperations == 0
    prepared = default(PreparedProgram)
    assert close(runtime)
    continue
  # A missed nomination must fail before entering the blocking witness gate.
  assert runtimeInfo(runtime).submitted == 1
  let parked = waitNativeCompilerGate(runtime)
  assert parked.point == NativeCompilerPoint.AfterPublish and parked.hasImage
  assert parked.kind == (if closed: NativeKind.ClosedRegisterLoop else: NativeKind.CheckedReadBody)
  let before = runtimeInfo(runtime)
  assert before.submitted == 1 and before.completed == 1 and before.completions == 1
  assert preparedInfo(prepared).value.nativeCalls == 0
  releaseNativeCompilerGate(runtime)
  let ready = executeWithHost(source, called, noHost, Quota, HostCallLimit(0), prepared)
  verifyOutcome(ready, source, page)
  assert not called and ready.value.backend == PvmBackend.Jit
  let owner = preparedInfo(prepared).value
  assert owner.nativeFragments == 1
  if closed:
    # Loop operations include its original checked branch in each visit receipt.
    assert owner.nativeCalls == 1 and owner.nativeOperations == 3*LoopTrips
    assert owner.nativeBranchCalls == 1 and owner.nativeHeaderCalls == 1
  else:
    # Read operations count only the three staged body operations.
    assert owner.nativeCalls == ReadTrips and owner.nativeOperations == 3*ReadTrips
    assert owner.nativeBranchCalls == 0 and owner.nativeHeaderCalls == 0
  if not closed:
    # Leave four attempts for the five-fact read block, then give it exactly five.
    # Both runs exhaust quota, but only the full reservation may call the ready body.
    let checked = newPreparedProgram(code, defaultPreparedLimits(GasCycleLimit(1000)),
      PvmBackend.Interpreted, default(NativeRuntime))
    assert checked.error == PreparationError.None
    for tail in [4'u64, 5'u64]:
      let quota = ExecutionStepLimit(3*LoopTrips+tail)
      let baseline = executeWithHost(source, called, noHost, quota, HostCallLimit(0), checked.value)
      let limited = executeWithHost(source, called, noHost, quota, HostCallLimit(0), prepared)
      assert not called and baseline.error == StepError.StepLimitExceeded
      assert limited.error == baseline.error
      let boundary = preparedInfo(prepared).value
      let committed = if tail == 5: 1'u64 else: 0'u64
      assert boundary.nativeCalls == owner.nativeCalls+committed
      assert boundary.nativeOperations == owner.nativeOperations+3*committed
    # Start at the same canonical read header to test the ready invocation floor separately.
    let interior = captureMachine(code, memory.value, MachineInfo(pc: CodeAddress(12),
      gas: MachineGas(GasStart), registers: registers)).value
    let beforeFloor = preparedInfo(prepared).value
    for budget in [4095'u64, 4096'u64]:
      let quota = ExecutionStepLimit(budget)
      let baseline = executeWithHost(interior, called, noHost, quota, HostCallLimit(0),
        checked.value)
      let limited = executeWithHost(interior, called, noHost, quota, HostCallLimit(0), prepared)
      assert not called and baseline.error == StepError.StepLimitExceeded
      assert limited.error == baseline.error
      let boundary = preparedInfo(prepared).value
      # Five read-block attempts plus two counter attempts make each complete round.
      let committed = if budget == 4096: 585'u64 else: 0'u64
      assert boundary.nativeCalls == beforeFloor.nativeCalls+committed
      assert boundary.nativeOperations == beforeFloor.nativeOperations+3*committed
    when defined(pvmX86Jit):
      # Page 34 is unmapped, then inaccessible, then readable but outside the three native extents.
      let initial = machineInfo(source).value
      verifyReadyReadFallback(code, prepared, checked.value, initial, [page], StepExit.Fault)
      var late = PageImage(index: PageIndex(34), access: PageAccess.Inaccessible)
      late.bytes[0] = 0x78
      late.bytes[7] = 0x12
      verifyReadyReadFallback(code, prepared, checked.value, initial, [page, late], StepExit.Fault)
      late.access = PageAccess.ReadOnly
      verifyReadyReadFallback(code, prepared, checked.value, initial, [page, late], StepExit.Halt)
      let beforeRecovery = preparedInfo(prepared).value
      let recovered = executeWithHost(source, called, noHost, Quota, HostCallLimit(0), prepared)
      verifyOutcome(recovered, source, page)
      assert not called and recovered.value.backend == PvmBackend.Jit
      let recoveredInfo = preparedInfo(prepared).value
      assert recoveredInfo.nativeFragments == beforeRecovery.nativeFragments
      assert recoveredInfo.nativeCalls == beforeRecovery.nativeCalls+ReadTrips
      assert recoveredInfo.nativeOperations == beforeRecovery.nativeOperations+3*ReadTrips
  let after = runtimeInfo(runtime)
  assert after.submitted == 1 and after.completed == 1 and after.completions == 0
  prepared = default(PreparedProgram)
  assert runtimeInfo(runtime).registered == 0 and close(runtime)
when NativeCheckedReadEnabled:
  proc continuationCertificate(code: Program, info: NativeReadBodyInfo,
      continuation: NativeReadContinuation, changedOperand = false): NativeReadBody =
    ## Rebuild the literal request from genuine decoded operands, permitting one deliberate stale scalar.
    result = initNativeReadBody(info.header, info.terminal, info.first, info.last, info.epoch)
    for index, pc in [1'u64, 4, 7]:
      # Each original read has its own ordered node/fact coordinate and signed immediate bits.
      let decoded = instruction(code, CodeAddress(pc))
      assert decoded.error == ProgramError.None, "decode original continuation read"
      assert addReadBodyOperation(result, info.header+1+uint32(index), info.first+1+uint32(index),
        NativeOperation(opcode: decoded.value.opcode, slots: instructionRegisters(decoded),
          immediate: uint64(decoded.value.x))), "rebuild original continuation read"
    var operations = default(array[3, NativeOperation])
    for index, pc in [11'u64, 14, 17]:
      # The final ADD immediate supplies a valid but source-inconsistent negative certificate.
      let decoded = instruction(code, CodeAddress(pc))
      assert decoded.error == ProgramError.None, "decode original pure continuation"
      operations[index] = NativeOperation(opcode: decoded.value.opcode,
        slots: instructionRegisters(decoded), immediate: uint64(decoded.value.x))
    if changedOperand:
      assert operations[2].immediate < high(uint64), "bound the deliberate stale immediate"
      inc operations[2].immediate
    assert addNativeReadContinuation(result, continuation, operations), "rebuild complete continuation"

  proc verifyContinuationSegment(frame: var FlatFrame, plan: FlatPlan, page: PageImage,
      cpu: MachineInfo, attempts, commits: uint64, reason: StepError, exit: StepExit,
      pc: uint32) =
    ## Compare one segment under the retained native lease with a fresh checked-only frame.
    var checked = newFlatFrame(plan, [page], cpu)
    runFlat(checked, attempts)
    let before = nativeStatistics(frame.nativeSession)
    resetFlatFrame(frame, cpu)
    runFlat(frame, attempts)
    assert frame.reason == reason and frame.reason == checked.reason, "continuation step reason"
    assert frame.exit == exit and frame.exit == checked.exit, "continuation exit"
    assert frame.remaining == checked.remaining, "continuation attempts"
    assert uint32(frame.faultPage) == uint32(checked.faultPage), "continuation fault page"
    let actual = frame.info
    let expected = checked.info
    assert uint64(actual.pc) == uint64(pc) and uint64(actual.pc) == uint64(expected.pc),
      "continuation PC"
    assert uint64(actual.gas) == uint64(expected.gas) and
      uint64(actual.gasDeficit) == uint64(expected.gasDeficit), "continuation gas"
    assert actual.blockCharged == expected.blockCharged, "continuation paid reservation"
    for slot in 0..<actual.registers.len:
      assert uint64(actual.registers[slot]) == uint64(expected.registers[slot]),
        "continuation registers"
    let memory = flatMemorySnapshot(frame)
    let current = pageImage(memory, page.index)
    assert current.error == MachineError.None and current.value.access == page.access and
      current.value.bytes == page.bytes, "continuation page contents and permissions"
    let after = nativeStatistics(frame.nativeSession)
    assert after[0] == before[0] and after[3] == before[3], "one retained continuation image"
    assert after[1] == before[1]+commits and after[2] == before[2]+6*commits,
      "three read ops and three successor ops per combined commit"

  block continuation:
    # A has a folded noop and three reads, with the wide read last at PC7. B at PC11
    # has three scalar operations and the checked fallthrough at PC20 to the loop counter.
    # PC29 jumps directly to B, and the loop counter starts at one for the short segments.
    const
      ReadFacts = 5'u64
      SuccessorFacts = 4'u64
      SuccessorPc = 11'u32
      CounterPc = 21'u32
      TrainBudget = ReadTrips*(ReadFacts+SuccessorFacts+2)+1
      ContinuationWire = [0'u8, 0, 31, 2, 124, 0x41, 0, 129, 0x42, 0, 130, 0x53, 1, 1,
        51, 6, 8, 200, 0x16, 7, 149, 0x77, 1, 1, 149, 0x88, 0xff, 82, 8, 0xe8, 50, 0,
        40, 0xee, 0x93, 0x4c, 0x32, 0x29]
    let decoded = decodeProgram(ContinuationWire, CodeAddress(0), ProgramByteLimit(64),
      JumpCountLimit(0))
    assert decoded.error == ProgramError.None, "decode continuation fixture"
    let code = decoded.value
    let cycles = GasCycleLimit(1000)
    var prepared = prepareFlatPlan(code, cycles, defaultFlatLimits(), false)
    assert prepared.error == FlatError.None, "prepare continuation fixture"
    let plan = takeValue(prepared)
    let readPrice = blockGas(code, CodeAddress(0), cycles)
    let successorPrice = blockGas(code, CodeAddress(uint64(SuccessorPc)), cycles)
    assert readPrice.error == GasError.None and successorPrice.error == GasError.None and
      uint64(successorPrice.value) > 0, "price both ordinary headers"
    let exactGas = uint64(readPrice.value)+uint64(successorPrice.value)
    var cpu = MachineInfo(pc: CodeAddress(0), gas: MachineGas(GasStart),
      registers: default(RegisterFile))
    cpu.registers[0] = RegisterValue(0xffff0000)
    cpu.registers[3] = RegisterValue(0x12345678)
    cpu.registers[4] = RegisterValue(0x20000)
    cpu.registers[5] = RegisterValue(0x20000)
    cpu.registers[8] = RegisterValue(1)
    var page = PageImage(index: PageIndex(32), access: PageAccess.ReadOnly)
    page.bytes[0] = 0x91
    page.bytes[8] = 0x12
    let runtime = newNativeRuntime()
    try:
      assert start(runtime), "start continuation compiler"
    except:
      assert false, "continuation compiler failed to start"
    let session = newNativeSession(runtime)

    # Train through the production probe with enough visits after its initial work floor.
    var trainingCpu = cpu
    trainingCpu.registers[8] = RegisterValue(ReadTrips)
    pauseNativeCompiler(runtime, true)
    let blockerMemory = captureMemory([page], PageLimit(1)).value
    let blockerSource = captureMachine(code, blockerMemory, trainingCpu).value
    var blocker = newPreparedProgram(code, defaultPreparedLimits(cycles), PvmBackend.Jit, runtime).value
    var called = false
    let blocked = executeWithHost(blockerSource, called, noHost, ExecutionStepLimit(TrainBudget),
      HostCallLimit(0), blocker)
    assert not called and blocked.error == StepError.None and blocked.value.exit ==
        StepExit.Halt and
      runtimeInfo(runtime).submitted == 1, "occupy compiler before extended read nomination"
    var training = newFlatFrame(plan, [page], trainingCpu)
    training.nativeSession = session
    beginNativeInvocation(session, TrainBudget)
    beginReadProbe(training, TrainBudget)
    runFlat(training, TrainBudget)
    assert training.reason == StepError.None and training.exit == StepExit.Halt and
      training.remaining == 0, "train the complete A and B shapes"
    endReadProbeSegment(training)
    recordNativeWork(session, settledNativeWork(training, TrainBudget))
    finishReadProbe(training, true)
    assert nativeReadContinuation(session).terminal != 0, "nominate the complete optional continuation"
    var stream = takeFlatStream(training)
    finishNativeInvocation(session, observedNativeWork(session))
    assert runtimeInfo(runtime).submitted == 1 and nativeState(session) == NativeState.Deferred,
      "retain the extended read while compiler work is occupied"
    pauseNativeCompiler(runtime, false)
    waitNativeCompiler(runtime)
    armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
    beginNativeInvocation(session, TrainBudget)
    var retry = newFlatFrame(plan, [page], trainingCpu)
    retry.nativeSession = session
    restoreFlatStream(retry, stream)
    assert deferredNativeReadInfo(session).epoch != 0 and
      nativeReadContinuation(session).terminal != 0, "restore the saved extended read geometry"
    let retained = deferredNativeReadInfo(session)
    let savedContinuation = nativeReadContinuation(session)
    assert validateNativeRead(session, continuationCertificate(code, retained, savedContinuation)),
      "exact decoded continuation certificate validates"
    var changedPrice = savedContinuation
    assert changedPrice.price < high(uint64), "bound the deliberate stale continuation price"
    inc changedPrice.price
    assert not validateNativeRead(session, continuationCertificate(code, retained, changedPrice)),
      "same epoch and geometry cannot authorize a stale continuation price"
    assert not validateNativeRead(session, continuationCertificate(code, retained,
        savedContinuation, true)),
      "same epoch and geometry cannot authorize a stale continuation operand"
    stream = takeFlatStream(retry)
    restoreFlatStream(retry, stream) # Only genuine restored source facts restore this invocation's validation.
    runFlat(retry, TrainBudget)
    assert retry.reason == StepError.None and retry.exit == StepExit.Halt and retry.remaining == 0,
      "complete checked retry of the extended read"
    recordNativeWork(session, settledNativeWork(retry, TrainBudget))
    stream = takeFlatStream(retry)
    finishNativeInvocation(session, observedNativeWork(session))
    assert runtimeInfo(runtime).submitted == 2, "request one retained continuation image"
    let parked = waitNativeCompilerGate(runtime)
    releaseNativeCompilerGate(runtime)
    assert parked.hasImage and parked.kind == NativeKind.CheckedReadBody,
      "worker must publish the checked read kind"

    # Segment budgets may be shorter than the invocation lease after a checked host boundary.
    var frame = newFlatFrame(plan, [page], cpu)
    frame.nativeSession = session
    beginNativeInvocation(session, TrainBudget)
    restoreFlatStream(frame, stream)
    assert nativeReadInfo(session).epoch != 0 and nativeReadContinuation(session).terminal != 0,
      "collect an extended read certificate"
    assert nativeStatistics(session)[0] == 1, "one collected continuation image"
    var fault = cpu
    fault.registers[5] = RegisterValue(0x22000)
    verifyContinuationSegment(frame, plan, page, fault, ReadFacts+SuccessorFacts, 0,
      StepError.None, StepExit.Fault, 7)
    assert uint32(frame.faultPage) == 0x22000, "late read faults on the unmapped page"

    # The four partial boundaries replay checked. The complete reservation reaches the next header.
    for remaining in 0'u64..SuccessorFacts:
      let nextPc = if remaining < SuccessorFacts: SuccessorPc+3*uint32(remaining) else: CounterPc
      let commits = if remaining == SuccessorFacts: 1'u64 else: 0'u64
      verifyContinuationSegment(frame, plan, page, cpu, ReadFacts+remaining, commits,
        StepError.StepLimitExceeded, StepExit.Continued, nextPc)
    verifyContinuationSegment(frame, plan, page, fault, ReadFacts+SuccessorFacts, 0,
      StepError.None, StepExit.Fault, 7)

    # Zero successor attempts stop before pricing. Positive partial quota still checks gas first.
    var priced = cpu
    priced.gas = MachineGas(exactGas-1)
    verifyContinuationSegment(frame, plan, page, priced, ReadFacts, 0,
      StepError.StepLimitExceeded, StepExit.Continued, SuccessorPc)
    verifyContinuationSegment(frame, plan, page, priced, ReadFacts+2, 0,
      StepError.None, StepExit.OutOfGas, SuccessorPc)
    priced.gas = MachineGas(exactGas)
    verifyContinuationSegment(frame, plan, page, priced, ReadFacts+SuccessorFacts+1, 1,
      StepError.None, StepExit.OutOfGas, CounterPc)
    assert uint64(frame.info.gas) == 0, "charge the complete successor exactly once"

    # Starting at B or reaching it through the independent jump keeps the checked route.
    for entry in [SuccessorPc, 29'u32]:
      var alternate = cpu
      alternate.pc = CodeAddress(uint64(entry))
      verifyContinuationSegment(frame, plan, page, alternate, 32, 0,
        StepError.None, StepExit.Halt, 0)
    finishNativeInvocation(session, 0)
    assert close(runtime), "close the continuation compiler after the invocation"
    blocker = default(PreparedProgram)

when NativeCheckedReadEnabled:
  proc startRetryCompiler(runtime: NativeRuntime) =
    ## Thread startup failure is a qualification failure, never an unsupported-host skip.
    try:
      assert start(runtime), "retry compiler startup"
    except:
      assert false, "retry compiler thread could not start"

  proc retrySource(closed = false): Machine =
    ## Reuse the literal fixture with an equivalent prefix predicate, optionally eligible for loop promotion.
    var wire = Wire
    wire[9] = if closed: 172'u8 else: 171'u8
    let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
    assert decoded.error == ProgramError.None, "retry source decode"
    var registers = default(RegisterFile)
    registers[0] = RegisterValue(0xffff0000)
    registers[5] = RegisterValue(0x20000)
    registers[8] = RegisterValue(0x20000)
    registers[9] = RegisterValue(ReadTrips)
    registers[11] = RegisterValue(LoopTrips)
    var page = PageImage(index: PageIndex(32), access: PageAccess.ReadOnly)
    for index, value in [0x10'u8, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe]:
      # A complete known qword also supplies the independent narrower read literals.
      page.bytes[index] = value
    let memory = captureMemory([page], PageLimit(1))
    assert memory.error == MachineError.None, "retry source memory"
    let made = captureMachine(decoded.value, memory.value, MachineInfo(pc: CodeAddress(0),
      gas: MachineGas(GasStart), registers: registers))
    assert made.error == MachineError.None, "retry source machine"
    made.value

  proc retryPrepared(source: Machine, runtime: NativeRuntime): PreparedProgram =
    ## Independent prepared identities share immutable code but never a native ticket or stream lease.
    let made = newPreparedProgram(source.programOf.value, defaultPreparedLimits(GasCycleLimit(1000)),
      PvmBackend.Jit, runtime)
    assert made.error == PreparationError.None, "retry prepared owner"
    made.value

  proc compareRetry(actual, expected, source: Machine) =
    ## Preserve complete observable CPU, code identity, bytes and permissions across every retry history.
    let a = actual.machineInfo.value
    let b = expected.machineInfo.value
    assert uint64(a.pc) == uint64(b.pc) and uint64(a.gas) == uint64(b.gas) and
      uint64(a.gasDeficit) == uint64(b.gasDeficit) and a.blockCharged == b.blockCharged,
      "retry complete CPU"
    for slot in 0..<13:
      # Every register participates even when the native read body writes only three lanes.
      assert uint64(a.registers[slot]) == uint64(b.registers[slot]), "retry all registers"
    assert actual.programOf.value == source.programOf.value, "retry source identity"
    let original = source.memoryOf.value.pageImage(PageIndex(32)).value
    for snapshot in [actual.memoryOf.value, expected.memoryOf.value]:
      # The read program has exactly one immutable page; no descriptor can manufacture another mapping.
      let indices = pageIndices(snapshot).value
      assert indices.len == 1 and uint32(indices[0]) == 32, "retry complete mapping"
      let page = pageImage(snapshot, PageIndex(32)).value
      assert page.access == original.access and page.bytes == original.bytes, "retry complete RAM"

  proc runRetry(source: Machine, code: PreparedProgram, budget = Quota): StepResult =
    ## Public host execution never waits for compilation; the literal fixture must not call its host.
    var called = false
    result = executeWithHost(source, called, noHost, budget, HostCallLimit(0), code)
    assert not called, "retry empty host history"

  proc trainRetryFrame(frame: var FlatFrame, session: NativeSession) =
    ## Obtain a genuine nomination from the existing bounded production probe before retaining its stream.
    frame.nativeSession = session
    beginNativeInvocation(session, uint64(Quota))
    beginReadProbe(frame, uint64(Quota))
    runFlat(frame, uint64(Quota))
    assert frame.reason == StepError.None and frame.exit == StepExit.Halt,
      "retry checked training frame"
    endReadProbeSegment(frame)
    recordNativeWork(session, settledNativeWork(frame, uint64(Quota)))
    finishReadProbe(frame, true)
    assert deferredNativeReadInfo(session).epoch == nativeEpoch(session),
      "retry genuine source-bound read nomination"

  block retainedReadContention:
    # An unrelated queued read occupies the only work slot while the second source qualifies.
    if nativePlatformSupported():
      let runtime = newNativeRuntime()
      startRetryCompiler(runtime)
      pauseNativeCompiler(runtime, true)
      let source = retrySource()
      let page = source.memoryOf.value.pageImage(PageIndex(32)).value
      var blocker = retryPrepared(source, runtime)
      let blocked = runRetry(source, blocker)
      verifyOutcome(blocked, source, page)
      assert runtimeInfo(runtime).submitted == 1, "retry occupied work slot"
      var owner = retryPrepared(source, runtime)
      for attempt in 0..<2:
        # Only the first call discovers candidates; the second must restore the nonempty stream.
        let done = runRetry(source, owner)
        verifyOutcome(done, source, page)
        assert done.value.backend == PvmBackend.Interpreted and
          runtimeInfo(runtime).submitted == 1, "retry defers while compiler is occupied"
      pauseNativeCompiler(runtime, false)
      waitNativeCompiler(runtime) # Existing deterministic barrier, outside public invocation clocks.
      let short = withRegister(withRegister(source, RegisterIndex(9), RegisterValue(1)).value,
        RegisterIndex(11), RegisterValue(1)).value
      let checked = newPreparedProgram(source.programOf.value, defaultPreparedLimits(GasCycleLimit(
          1000)),
        PvmBackend.Interpreted).value
      let shortExpected = runRetry(short, checked)
      let shortActual = runRetry(short, owner)
      assert shortExpected.error == StepError.None and shortActual.error == StepError.None,
        "retry short successful public calls"
      compareRetry(shortActual.value.machine, shortExpected.value.machine, short)
      assert uint64(shortActual.value.machine.machineInfo.value.registers[6]) == 1 and
        runtimeInfo(runtime).submitted == 1, "short work must not replace the retained read with pure"
      let failed = runRetry(source, owner, ExecutionStepLimit(4096))
      assert failed.error == StepError.StepLimitExceeded and runtimeInfo(runtime).submitted == 1,
        "failed public call cannot submit the retained read or its weaker pure prefix"
      armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
      let retried = runRetry(source, owner)
      verifyOutcome(retried, source, page)
      assert runtimeInfo(runtime).submitted == 2, "one retained read retry request"
      let parked = waitNativeCompilerGate(runtime)
      releaseNativeCompilerGate(runtime)
      assert parked.hasImage and parked.kind == NativeKind.CheckedReadBody,
        "retry must publish the retained read rather than its pure prefix"
      let ready = runRetry(source, owner)
      verifyOutcome(ready, source, page)
      assert ready.value.backend == PvmBackend.Jit, "retry real public native read"
      let info = preparedInfo(owner).value
      assert info.nativeFragments == 1 and info.nativeCalls == ReadTrips and
        info.nativeOperations == 3*ReadTrips, "retry exact completed native activity"
      let evidence = getEnv("RAGNAROK_TEST_EVIDENCE")
      if evidence.len > 0:
        # Only a supported actual native public path writes this numeric proof.
        let isa = when defined(pvmX86Jit): "x86_64" else: "arm64"
        try:
          writeFile(evidence & "/pvm_read_retry_" & isa & ".json",
            "{\"schema\":1,\"isa\":\"" & isa & "\",\"fragments\":" & $info.nativeFragments &
            ",\"calls\":" & $info.nativeCalls & ",\"operations\":" & $info.nativeOperations & "}\n")
        except:
          assert false, "retry native evidence could not be written"
      owner = default(PreparedProgram)
      blocker = default(PreparedProgram)
      assert runtimeInfo(runtime).registered == 0 and close(runtime), "retry owner retirement"

  block retainedReadLoopPrecedence:
    # A retained read must never displace a certified closed loop once the shared slot becomes available.
    if nativePlatformSupported():
      let runtime = newNativeRuntime()
      startRetryCompiler(runtime)
      pauseNativeCompiler(runtime, true)
      let source = retrySource(true)
      let page = source.memoryOf.value.pageImage(PageIndex(32)).value
      var blocker = retryPrepared(source, runtime)
      verifyOutcome(runRetry(source, blocker), source, page)
      var owner = retryPrepared(source, runtime)
      verifyOutcome(runRetry(source, owner), source, page)
      assert runtimeInfo(runtime).submitted == 1, "loop/read retry retains its nominations"
      pauseNativeCompiler(runtime, false)
      waitNativeCompiler(runtime)
      armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
      verifyOutcome(runRetry(source, owner), source, page)
      assert runtimeInfo(runtime).submitted == 2, "loop/read retry has one selected request"
      let parked = waitNativeCompilerGate(runtime)
      releaseNativeCompilerGate(runtime)
      assert parked.hasImage and parked.kind == NativeKind.ClosedRegisterLoop,
        "certified closed loop retains priority over a deferred read"
      let ready = runRetry(source, owner)
      verifyOutcome(ready, source, page)
      let info = preparedInfo(owner).value
      assert ready.value.backend == PvmBackend.Jit and info.nativeFragments == 1 and
        info.nativeCalls == 1 and info.nativeOperations == 3*LoopTrips,
        "loop/read retry enters the actual selected native loop"
      owner = default(PreparedProgram)
      blocker = default(PreparedProgram)
      assert close(runtime) and runtimeInfo(runtime).registered == 0, "loop/read retry retirement"

  block retainedReadLifecycle:
    # Explicit invalidation, deferred drop/close and a cancelled real image cover distinct ownership states.
    if nativePlatformSupported():
      for mode in 0..<4:
        let runtime = newNativeRuntime()
        startRetryCompiler(runtime)
        pauseNativeCompiler(runtime, true)
        let source = retrySource()
        var blocker = retryPrepared(source, runtime)
        verifyOutcome(runRetry(source, blocker), source,
          source.memoryOf.value.pageImage(PageIndex(32)).value)
        var admitted = prepareFlatPlan(source.programOf.value, GasCycleLimit(1000),
          defaultFlatLimits(), false)
        assert admitted.error == FlatError.None, "retry lifecycle source plan"
        let plan = takeValue(admitted)
        var made = prepareFlatMemoryFrame(plan, source.memoryOf.value, source.machineInfo.value)
        assert made.error == FlatError.None, "retry lifecycle training memory"
        var frame = takeValue(made)
        var session = newNativeSession(runtime)
        trainRetryFrame(frame, session)
        var stream = takeFlatStream(frame)
        frame.nativeSession = default(NativeSession)
        finishNativeInvocation(session, observedNativeWork(session))
        assert nativeState(session) == NativeState.Deferred and runtimeInfo(runtime).submitted == 1,
          "retry lifecycle deferred nomination is not a compiler request"
        if mode == 0 or mode == 3:
          # Reset invalidates the old read; the cancellation case first queues its exact retained request.
          let oldEpoch = nativeEpoch(session)
          if mode == 0:
            invalidateNativeStream(session)
            assert nativeEpoch(session) == oldEpoch+1, "retry source epoch advances"
          pauseNativeCompiler(runtime, false)
          waitNativeCompiler(runtime)
          armNativeCompilerGate(runtime, (if mode == 0: NativeCompilerPoint.AfterPublish else:
            NativeCompilerPoint.BeforePublish))
          beginNativeInvocation(session, uint64(Quota))
          var fresh = prepareFlatMemoryFrame(plan, source.memoryOf.value, source.machineInfo.value)
          assert fresh.error == FlatError.None, "retry lifecycle fresh frame"
          var current = takeValue(fresh)
          current.nativeSession = session
          restoreFlatStream(current, stream)
          assert deferredNativeReadInfo(session).epoch == (if mode == 0: 0'u64 else: oldEpoch),
            "retry source epoch determines retained nomination"
          beginReadProbe(current, uint64(Quota)) # Restored nodes must not trigger discovery.
          runFlat(current, uint64(Quota))
          assert current.reason == StepError.None and current.exit == StepExit.Halt,
            "retry lifecycle complete checked output"
          endReadProbeSegment(current)
          recordNativeWork(session, settledNativeWork(current, uint64(Quota)))
          finishReadProbe(current, true)
          stream = takeFlatStream(current)
          current.nativeSession = default(NativeSession)
          finishNativeInvocation(session, observedNativeWork(session))
          assert runtimeInfo(runtime).submitted == 2, "retry lifecycle sole replacement request"
          let parked = waitNativeCompilerGate(runtime)
          let expectedEpoch = nativeEpoch(session)
          if mode == 3:
            # Cancellation sees a real worker-local read image, which must never be collected.
            invalidateNativeStream(session)
            session = default(NativeSession)
          releaseNativeCompilerGate(runtime)
          waitNativeCompiler(runtime)
          assert parked.hasImage and parked.epoch == expectedEpoch and
            parked.kind == (if mode == 0: NativeKind.PurePrefix else: NativeKind.CheckedReadBody),
            "retry exact queued epoch and image kind"
          if mode == 3:
            assert runtimeInfo(runtime).completed == 1 and runtimeInfo(runtime).registered == 1,
              "retry cancelled image retires without disturbing the unrelated completion"
        elif mode == 2:
          # A closed anchor cannot submit a retained nomination, even if its caller returns a work receipt.
          assert close(runtime) and nativeState(session) == NativeState.Closed, "retry deferred close"
          beginNativeInvocation(session, uint64(Quota))
          finishNativeInvocation(session, uint64(Quota))
          assert runtimeInfo(runtime).submitted == 1, "retry closed source cannot submit"
        else:
          # No read ticket exists: last-drop releases its credit without waiting for the unrelated job.
          session = default(NativeSession)
          assert runtimeInfo(runtime).registered == 1 and runtimeInfo(runtime).submitted == 1,
            "retry deferred drop releases exactly its own registration"
        session = default(NativeSession)
        blocker = default(PreparedProgram)
        assert close(runtime) and runtimeInfo(runtime).registered == 0, "retry lifecycle retirement"

echo "PVM read arbitration and quota passed"
