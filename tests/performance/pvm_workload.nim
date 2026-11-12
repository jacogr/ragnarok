# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Canonical full requests include cold code/runtime admission and every call restoration/publication.
## Modern host fixtures explicitly select copied-CPU callbacks; legacy/foreign callbacks keep owned snapshots.

import std/[assertions, syncio, envvars, monotimes]
import ./pvm_invocation_scope
import ../../src/pvm/[program, machine]
import ../../src/pvm/gas/[gas, plan as gas_plan, memo as gas_memo]
import ../../src/pvm/step

proc cpuNanoseconds(): int64 {.importc: "pvm_sieve_cpu_nanoseconds",
    header: "pvm_sieve_clock.h".}
  ## Reuse the checked OS process clock; legacy observations keep their wall-only protocol.

type HostContext = object ## Plain host progress is included in both embeddings' execution time.
  calls: uint64

proc word(data: string, at, width: int): uint64 =
  ## Read fixed fields after their enclosing record extent is validated.
  result = 0
  for i in 0..<width:
    # Framing is independent of the production operand decoder.
    result = result or (uint64(byte(data[at + i])) shl (8 * i))

proc respondScalar(context: var HostContext, call: HostCallId,
    cpu: MachineInfo): ScalarHostResponse {.raises: [].} =
  ## Canonical register-only calls receive copied CPU state, matching the Rust embedding's needed capability.
  var registers = cpu.registers
  if uint64(call) == 13:
    # Host dispatch and reply construction are part of the measured embedding workload.
    registers[7] = RegisterValue(uint64(registers[7]) + 1)
  else:
    # Unexpected host identifiers are failures, never accepted timing samples.
    assert uint64(call) == 14
    registers[8] = RegisterValue(uint64(registers[8]) + uint64(registers[7]))
  inc context.calls
  ScalarHostResponse(action: HostAction.Continue, gas: cpu.gas,
      gasDeficit: GasDeficit(0),
    registers: registers)

func scalarBenchmarkHost(call: HostCallId): bool =
  ## Explicit caller capability: only the two authored register-only callbacks select scalar dispatch.
  uint64(call) in [13'u64, 14'u64]

proc respond(context: var HostContext, suspension: StepOutcome): HostResponse {.raises: [].} =
  ## Legacy execution and explicit foreign engines keep the original retainable snapshot contract.
  let cpu = machineInfo(suspension.machine).value
  let response = respondScalar(context, suspension.hostCall, cpu)
  HostResponse(action: response.action, gas: response.gas, gasDeficit: response.gasDeficit,
    registers: response.registers, memory: memoryOf(suspension.machine).value)

template runBenchmark(source: Machine, context: var HostContext, kind: uint64,
    steps: ExecutionStepLimit, hosts: HostCallLimit, cycles: GasCycleLimit,
    plannedMode: bool, plan: GasPlan, memo: GasMemo): StepResult =
  ## Instantiate memo host execution separately, preserving the established legacy driver.
  when defined(pvmBenchmarkMemo):
    if kind == 2: executeWithHost(source, context, respond, steps, hosts, memo)
    else: execute(source, steps, memo)
  else:
    if kind == 2:
      if plannedMode: executeWithHost(source, context, respond, steps, hosts, plan)
      else: executeWithHost(source, context, respond, steps, hosts, cycles)
    else:
      if plannedMode: execute(source, steps, plan)
      else: execute(source, steps, cycles)

# Every paired build must demonstrate that native assertions remain active before any timed execution.
if getEnv("RAGNAROK_PVM_BENCH_ASSERT_PROBE") == "1":
  assert false, "pvm synthetic native assertion control"

let fullInvocation = getEnv("RAGNAROK_PVM_PERFORMANCE") == "1"
if fullInvocation: fullInvocationHeader()

let requestedProtocol = getEnv("RAGNAROK_PVM_PERFORMANCE")
assert requestedProtocol in ["", "0", "1"]
let modern = requestedProtocol == "1"
let requestedBackend = getEnv("RAGNAROK_PVM_BACKEND")
var selectedBackend = DefaultPvmBackend
if modern:
  # One production image selects only the requested public owner policy at runtime.
  assert requestedBackend in ["interpreted", "jit"]
  assert parsePvmBackend(requestedBackend, selectedBackend)
let pricing = getEnv("RAGNAROK_PVM_PRICING")
when defined(pvmBenchmarkMemo):
  assert not modern and pricing == "memo",
      "pvm benchmark memo mode mismatch" # A separate driver instantiation avoids changing legacy host-loop code generation.
else:
  assert (if modern: pricing == "prepared" else: pricing in ["", "dynamic",
      "planned"]),
    "pvm benchmark legacy mode mismatch" # Reject accidental engine relabeling before any sample.
let plannedMode = pricing == "planned"
const memoMode = defined(pvmBenchmarkMemo)
var data = ""
try:
  # Missing input is a setup error and must never yield an empty timing result.
  data = readFile(getEnv("RAGNAROK_PVM_BENCHMARK"))
except:
  quit 2
assert data.len >= 12 and data[0..7] == "PVMBEN01" and word(data, 8, 4) == 11
var cursor = 12
let processOwnerStart = if fullInvocation: beginInvocation() else: default(InvocationClock)
var invocationRuntime = if fullInvocation and requestedBackend == "jit":
    startInvocationRuntime() else: default(InvocationRuntime)
for row in 0..<11:
  # Bound guest inputs before timing or narrowing; malformed corpora cannot create measurements.
  assert data.len - cursor >= 273
  let at = cursor
  let length = word(data, at, 4)
  let kind = byte(data[at + 4])
  let iterations = word(data, at + 5, 4)
  let address = word(data, at + 9, 4)
  let initial = word(data, at + 13, 8)
  let price = word(data, at + 29, 8)
  let cycles = word(data, at + 37, 8)
  let halt = word(data, at + 45, 4)
  let haltPrice = word(data, at + 49, 8)
  assert kind <= 5 and iterations > 0 and iterations <= 10000
  assert price > 0 and price < 1000 and haltPrice > 0 and haltPrice < 1000
  assert cycles > 0 and cycles < 1000
  let secondPrice = if kind == 5: initial else: 0'u64
  if kind == 5:
    # The memoryless alternating guest reuses auxiliary header slots for its independently specified second block.
    assert address == 8 and secondPrice > 0 and secondPrice < 1000
  cursor += 273
  assert length >= 4 and length <= 128 and length <= uint64(data.len - cursor)
  # Cold input admission and every code-specific constructor remain inside this SAME outer interval.
  let perLoop = case kind
    of 0: 3'u64
    of 1, 4: 5'u64
    of 3: 9'u64
    of 5: 4'u64
    else: 6'u64
  # Independent input/source oracles are fixture preparation, with no decoded or prepared owner.
  var originalCpu = MachineInfo(pc: CodeAddress(0),
    gas: MachineGas(iterations * (price+secondPrice) + haltPrice + 7), blockCharged: false,
    registers: default(RegisterFile))
  for i in 0..<13: originalCpu.registers[i] = RegisterValue(word(data, at + 65 + i*8, 8))
  var originalLayout: seq[PageDescription] = @[]
  if kind in [1'u8, 2, 4]:
    for page in 0..<(if kind == 4: 128 else: 2):
      let offset = if kind == 4: (page div 2)*4 + page mod 2 else: page
      originalLayout.add(PageDescription(index: PageIndex(uint32(16 + offset)),
          access: PageAccess.ReadWrite))
  let coldCall = if fullInvocation: beginInvocation() else: default(InvocationClock)
  let preparation = getMonoTime().ticks
  var wire: seq[byte] = @[]
  for i in 0..<int(length):
    # Program and memory admission happen once inside the enclosing cold invocation.
    wire.add(byte(data[cursor + i]))
  cursor += int(length)
  let program = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(128),
      JumpCountLimit(0)).value
  var memory = default(Memory)
  if kind in [1'u8, 2, 4]:
    # Copy the common pattern directly into final independent pages, preserving sparse holes.
    assert address in [0x10000'u64, 0x10fff'u64]
    var firstPair = default(array[8192, byte])
    var common = default(array[4096, byte])
    for index in 0..<firstPair.len: firstPair[index] = 33
    for index in 0..<common.len: common[index] = 33
    for index in 0..<8:
      # Only the first pair differs; the initial scalar may cross its page boundary.
      firstPair[int(address-0x10000)+index] = byte((initial shr (8*index)) and 255)
    let pageCount = if kind == 4: 128 else: 2
    var regions = newSeq[InitializationRegion](pageCount)
    for page in 0..<pageCount:
      let offset = if kind == 4: (page div 2)*4 + page mod 2 else: page
      regions[page] = InitializationRegion(first: PageIndex(uint32(16+offset)),
        past: PageIndex(uint32(17+offset)), access: PageAccess.ReadWrite,
        source: (if page < 2: InitializationSource.First else: InitializationSource.Second),
        offset: (if page < 2: page*4096 else: 0), length: 4096)
    memory = captureInitializationMemory(regions, firstPair, common, PageLimit(uint32(
        pageCount))).value
  else:
    # Non-memory workloads retain an empty independently owned mapping with the original limit.
    memory = captureMemory([], PageLimit(2)).value
  var registers = default(RegisterFile)
  for i in 0..<13: registers[i] = RegisterValue(word(data, at + 65 + i * 8, 8))
  let source = captureMachine(program, memory, MachineInfo(pc: CodeAddress(0),
    gas: MachineGas(iterations * (price+secondPrice) + haltPrice + 7),
        blockCharged: false, registers: registers)).value
  var preparationCpu = 0'i64
  var preparationWall = 0'i64
  var prepared = default(PreparedProgram)
  if modern:
    # A cold public owner admits source facts once; the first invocation retains all lazy work.
    let wallStart = getMonoTime().ticks
    let cpuStart = cpuNanoseconds()
    let created = newPreparedProgram(program, defaultPreparedLimits(
        GasCycleLimit(cycles)), selectedBackend, invocationRuntime)
    let cpuElapsed = cpuNanoseconds()-cpuStart
    let wallElapsed = getMonoTime().ticks-wallStart
    assert created.error == PreparationError.None
    prepared = created.value
    let cold = preparedInfo(prepared).value
    assert cold.streamNodes == 0 and cold.nativeFragments == 0 and
        cold.nativeCalls == 0
    assert cold.nativeOperations == 0 and cold.memoryReuses == 0
    if fullInvocation:
      if cpuElapsed < 0 or wallElapsed < 0:
        # Failure-only context is outside both clocks; a nested measured zero remains valid.
        echo "PVM_TIMING_FAILURE,1,full-invocation-v1,native,synthetic-constructor-", row,
          ",0,", cpuElapsed, ",", wallElapsed
      assert cpuElapsed >= 0 and wallElapsed >= 0
    else:
      assert cpuElapsed > 0, "pvm synthetic constructor CPU below clock resolution"
      assert wallElapsed > 0
    preparationCpu = cpuElapsed
    preparationWall = wallElapsed
  var plan = default(GasPlan)
  var memo = default(GasMemo)
  if plannedMode:
    # Complete immutable prices are prepared once per captured program and included in its native setup observation.
    let created = newGasPlan(program, GasPlanLimits(blocks: GasPlanBlockLimit(
        100000),
      bytes: GasPlanByteLimit(8*1024*1024), cycles: GasCycleLimit(cycles)))
    assert created.error == GasPlanError.None
    plan = created.value
  if memoMode:
    # The empty bounded memo is setup; first-sample execution includes all initially missing price work.
    let created = newGasMemo(program, GasMemoLimits(bytes: GasMemoByteLimit(
        8*1024*1024), cycles: GasCycleLimit(cycles)))
    assert created.error == GasMemoError.None
    memo = created.value
  let prepareNs = getMonoTime().ticks - preparation
  if plannedMode:
    let info = gasPlanInfo(plan).value
    echo "gas-plan\t", row, "\t", prepareNs, "\t", info.codeBytes, "\t",
        info.blockCount,
      "\t", info.payloadBytes, "\t", uint64(info.cycleLimit)
  if memoMode:
    let info = gasMemoInfo(memo).value
    assert info.pricedBlocks == 0
    echo "gas-memo\t", row, "\t", prepareNs, "\t", info.codeBytes, "\t",
        info.payloadBytes, "\t", uint64(info.cycleLimit)

  for sample in 0..<13:
    # Three warmups precede ten recorded samples; source owners are immutable across every run.
    let residentCall = if fullInvocation and sample != 0: beginInvocation() else: default(InvocationClock)
    let cpuStart = if fullInvocation: (if sample ==
        0: coldCall.cpu else: residentCall.cpu)
      elif modern: cpuNanoseconds() else: 0'i64
    let start = if fullInvocation: (if sample ==
        0: coldCall.wall else: residentCall.wall)
      else: getMonoTime().ticks
    var context = HostContext(calls: 0)
    let evaluated = if modern:
      # Kind 5 at 1,000 iterations keeps 4,001 attempts, below the 4,096 native invocation floor.
      # Admission requires both this call's budget and retained proven work to meet the floor.
      # Proven work keeps the maximum from a single completed call, never a lifetime sum.
      # The modern host role explicitly consumes scalar CPU callbacks; final owned publication stays timed.
      # Guest attempts, callback/context arithmetic and complete memory oracles are unchanged.
      if kind == 2:
        executeWithHost(source, context, respond, ExecutionStepLimit(
            perLoop*iterations+1),
          HostCallLimit(2*iterations), prepared, scalarBenchmarkHost, respondScalar)
      else: execute(source, ExecutionStepLimit(perLoop*iterations+1), prepared)
    else:
      runBenchmark(source, context, kind, ExecutionStepLimit(
          perLoop*iterations+1),
        HostCallLimit(2*iterations), GasCycleLimit(cycles), plannedMode, plan, memo)
    assert evaluated.error == StepError.None and evaluated.value.exit == StepExit.Halt
    let final = machineInfo(evaluated.value.machine).value
    let elapsed = getMonoTime().ticks - start
    let cpuElapsed = if modern: cpuNanoseconds()-cpuStart else: 0'i64
    if sample == 0:
      # Independent pricing/source oracles and receipt printing never enter the full clock.
      assert uint64(blockGas(program, CodeAddress(0), GasCycleLimit(
          cycles)).value) == price
      assert uint64(blockGas(program, CodeAddress(halt), GasCycleLimit(
          cycles)).value) == haltPrice
      if kind == 5:
        assert uint64(blockGas(program, CodeAddress(address), GasCycleLimit(
            cycles)).value) == secondPrice
      if modern: echo "SYNTHETIC_PREPARE,1,", row, ",", preparationCpu, ",", preparationWall
    # Complete result validation happens after the clock stops; failed outcomes never emit a sample.
    assert uint64(final.gas) == 7 and uint64(final.pc) == 0 and
        final.blockCharged
    assert uint64(final.gasDeficit) == 0
    assert context.calls == (if kind == 2: 2 * iterations else: 0'u64)
    for i in 0..<13:
      assert uint64(final.registers[i]) == word(data, at + 169 + i * 8, 8),
        "pvm synthetic terminal register mismatch"
      assert uint64(machineInfo(source).value.registers[i]) == uint64(registers[i])
    for page in 0..<originalLayout.len:
      # Full byte checks retain output observability and catch extra writes beyond the measured scalar.
      let actual = pageImage(memoryOf(evaluated.value.machine).value, PageIndex(
          uint32(16 + (if kind == 4: (page div 2)*4 +
              page mod 2 else: page)))).value
      assert actual.access == PageAccess.ReadWrite
      for i in 0..<4096:
        let physical = 0x10000'u64 + uint64((int(uint32(originalLayout[
            page].index))-16) * 4096 + i)
        let expected = if physical >= address and physical - address < 8:
          byte((word(data, at + 21, 8) shr (8 * int(physical - address))) and
              255) else: 33'u8
        assert actual.bytes[i] == expected
      let retained = pageImage(memoryOf(source).value, originalLayout[page].index).value
      assert retained.access == PageAccess.ReadWrite
      for index in 0..<4096:
        # Derive the original byte independently from the fixture, without retaining a staging copy.
        let physical = uint64(uint32(originalLayout[page].index))*4096 + uint64(index)
        let expected = if physical >= address and physical-address < 8:
          byte((initial shr (8*int(physical-address))) and 255) else: 33'u8
        assert retained.bytes[index] == expected
    if kind == 4:
      for pair in 0..<64:
        # Unmapped holes remain faults in both the retained source and final immutable result.
        let hole = MemoryAddress(uint64(0x12000 + pair*16384))
        assert load(memoryOf(source).value, hole, AccessWidth(1)).error ==
            MachineError.Fault
        assert load(memoryOf(evaluated.value.machine).value, hole, AccessWidth(
            1)).error == MachineError.Fault
    assert machineInfo(source).value == originalCpu
    assert memoryLayout(memoryOf(evaluated.value.machine).value).value == originalLayout
    assert memoryLayout(memoryOf(source).value).value == originalLayout
    if fullInvocation and (cpuElapsed <= 0 or elapsed <= 0):
      # Preserve the exact failed primary observation before the unchanged positivity guards.
      echo "PVM_TIMING_FAILURE,1,full-invocation-v1,native,synthetic-", row, ",", sample,
        ",", cpuElapsed, ",", elapsed
    assert elapsed > 0
    if modern:
      # Emit genuine CPU and wall deltas only after all independent state/source checks pass.
      assert cpuElapsed > 0, "pvm synthetic execution CPU below clock resolution"
      echo "SYNTHETIC_SAMPLE,1,", row, ",", sample, ",", cpuElapsed, ",", elapsed
    else:
      # Historical consumers retain their wall-only sample framing.
      echo "sample\t", row, "\t", sample, "\t", elapsed, "\t", prepareNs
  if memoMode:
    # A complete final occupancy witness distinguishes a warmed reusable memo from per-call dynamic pricing.
    echo "gas-memo-end\t", row, "\t", gasMemoInfo(memo).value.pricedBlocks
  if modern:
    # Idle public diagnostics report actual completed work, including honest interpreted fallback.
    let policy = preparedInfo(prepared).value
    assert policy.backend == selectedBackend
    let actual = if policy.nativeOperations > 0: "jit" else: "interpreted"
    reportNativeCompilation("synthetic-" & $row,
        policy.nativeCompilationMeasured, policy.nativeCompilationNs)
    echo "SYNTHETIC_NATIVE,1,", row, ",", policy.nativeFragments, ",",
        policy.nativeCalls, ",",
      policy.nativeOperations, ",", policy.nativeCodeBytes, ",",
          policy.nativeCompilationNs
    echo "SYNTHETIC_POLICY,1,", row, ",", requestedBackend, ",", int(
        policy.jitBuilt), ",",
      int(policy.jitPlatformSupported), ",", int(policy.checkedFallbackEnabled),
          ",", actual, ",",
      policy.nativeFragments, ",", policy.nativeCalls, ",",
          policy.nativeOperations

if fullInvocation:
  if requestedBackend == "jit":
    closeInvocationRuntime(invocationRuntime, "synthetic-process", processOwnerStart, 11)
  else:
    finishInterpretedOwner("synthetic-process", processOwnerStart, 11)
assert cursor == data.len
if modern: echo "SYNTHETIC_OK,1,", requestedBackend
