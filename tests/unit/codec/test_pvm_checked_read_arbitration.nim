# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Same-owner loop/read arbitration with one shape invalidated in the paired case.
import std/[assertions, syncio]
import ../../../src/pvm/[machine, program, step]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/internal/native_pipeline

const
  LoopTrips = 1400'u64
  ReadTrips = 40000'u64
  GasStart = 3000000'u64
  # Both unsigned branches have UNLIKELY successors and cost one pipeline cycle.
  # The prefix and counter blocks each charge 3. The independent-read block charges 40.
  EndGas = GasStart-3*LoopTrips-43*ReadTrips-22
  Quota = ExecutionStepLimit(300000)
  # PC0 and PC3 ADD_IMM_32, PC6 BRANCH_LT_U to PC0, then PC12 begins the read block.
  # PC12..19 UNLIKELY, U8, S32, U64, FALLTHROUGH. PC20 increments R6, PC23 loops to PC12.
  # PC29 JUMP_IND R0,0 halts. Offset nine in the wire is exactly the prefix branch opcode.
  Wire = [0'u8, 0, 31, 131, 0x77, 3, 131, 0xaa, 1, 172, 0xba, 0xfa, 0xff, 0xff, 0xff,
    2, 124, 0x53, 129, 0x52, 130, 0x54, 1, 131, 0x66, 1, 172, 0x96, 0xf5, 0xff, 0xff, 0xff,
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
  try:
    assert start(runtime)
  except:
    assert false, "read arbitration worker failed to start"
  var prepared = default(PreparedProgram)
  block:
    let created = newPreparedProgram(code, defaultPreparedLimits(GasCycleLimit(1000)),
      PvmBackend.Jit, runtime)
    assert created.error == PreparationError.None
    prepared = created.value
  var called = false
  armNativeCompilerGate(runtime, NativeCompilerPoint.AfterPublish)
  let trained = executeWithHost(source, called, noHost, Quota, HostCallLimit(0), prepared)
  verifyOutcome(trained, source, page)
  assert not called and trained.value.backend == PvmBackend.Interpreted
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
  let after = runtimeInfo(runtime)
  assert after.submitted == 1 and after.completed == 1 and after.completions == 0
  prepared = default(PreparedProgram)
  assert runtimeInfo(runtime).registered == 0 and close(runtime)
echo "PVM read arbitration and quota passed"
