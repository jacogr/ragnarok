# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Invocation-local decoded operands survive collisions, capacity pressure and host resumptions without crossing programs or callback nesting.
# @@Verification={"arc": "pvm_execution_cache_arc_release"}
import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, gas, gas_plan, gas_memo, step]
import ../../support/arc_evidence

type
  Reason = enum ## Callback failure remains local and typed after previous host side effects.
    Refused
  Context = object ## Nested immutable input and scalar progress belong only to the synchronous test caller.
    nested: Machine
    calls: int
    refuse: bool
proc code(parts: openArray[seq[byte]]): Program =
  ## Independently frame original instruction partitions; literal bytes and explicit masks never come from the production decoder.
  var bytes: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    starts.add(bytes.len)
    for octet in part: bytes.add(octet)
  assert bytes.len > 0 and bytes.len < 16384
  var wire = @[0'u8, 0]
  if bytes.len < 128:
    wire.add(byte(bytes.len)) # The original fixtures retain their canonical one-byte length.
  else:
    wire.add(byte(128+(bytes.len shr 8))) # Independent two-byte JAM framing covers bounded capacity-pressure programs.
    wire.add(byte(bytes.len and 255))
  for octet in bytes: wire.add(octet)
  var mask = newSeq[byte]((bytes.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for octet in mask: wire.add(octet)
  let captured = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(32768), JumpCountLimit(0))
  assert captured.error == ProgramError.None
  captured.value
proc input(program: Program, count: uint64, charged = false): Machine =
  ## Explicit CPU sentinels and a genuine empty memory owner distinguish valid execution from default handles.
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(count)
  registers[2] = RegisterValue(0xffff0000'u64)
  captureMachine(program, captureMemory([], PageLimit(0)).value, MachineInfo(pc: CodeAddress(0),
      gas: MachineGas(high(uint64)), blockCharged: charged, registers: registers)).value
proc same(actual, expected: MachineInfo) =
  ## Complete CPU parity includes every untouched register, unsigned gas and paid-block flag.
  assert uint64(actual.pc) == uint64(expected.pc)
  assert uint64(actual.gas) == uint64(expected.gas)
  assert uint64(actual.gasDeficit) == uint64(expected.gasDeficit)
  assert actual.blockCharged == expected.blockCharged
  for index in 0..<13: assert uint64(actual.registers[index]) == uint64(expected.registers[index])
proc compareSteps(source: Machine, attempts: int, terminal = StepExit.Panic,
    cycles = GasCycleLimit(10000)): MachineInfo =
  ## Public single-step execution never uses the invocation cache; its complete trace independently checks composition and exit normalization.
  assert attempts > 0
  result = default(MachineInfo) # Initialize the copied result even before the bounded positive trace is traversed.
  var current = source
  for index in 0..<attempts:
    let once = stepOnce(current, cycles)
    assert once.error == StepError.None
    if index+1 == attempts:
      assert once.value.exit == terminal
      result = machineInfo(once.value.machine).value
      if terminal in {StepExit.Panic, StepExit.Halt}:
        result.pc = CodeAddress(0) # Outer Psi normalizes final Panic/Halt while retaining all posterior CPU values.
      elif terminal == StepExit.Host:
        result.pc = machineInfo(current).value.pc # Recursive host publication retains the independently stepped causing PC.
    else:
      assert once.value.exit == StepExit.Continued
      current = once.value.machine
proc collisions() =
  ## PCs0 and16 deliberately share a direct slot; later capacity pressure visits more distinct instructions than retained slots.
  var decrement = @[149'u8, 0, 255, 255, 255, 255]
  while decrement.len < 16: decrement.add(0) # Only ignored trailing operands are padded; the four-byte immediate remains literal minus one.
  let program = code([decrement, @[82'u8, 16, 0, 240], @[0'u8]])
  let source = input(program, 23)
  let run = execute(source, ExecutionStepLimit(47), GasCycleLimit(10000))
  assert run.error == StepError.None and run.value.exit == StepExit.Panic
  same(machineInfo(run.value.machine).value, compareSteps(source, 47))
  assert uint64(machineInfo(run.value.machine).value.registers[0]) == 0
  assert uint64(machineInfo(source).value.registers[0]) == 23
  assert execute(source, ExecutionStepLimit(46), GasCycleLimit(10000)).error ==
      StepError.StepLimitExceeded
  assert execute(source, ExecutionStepLimit(47), GasCycleLimit(0)).error ==
      StepError.GasCycleLimitExceeded
  var parts: seq[seq[byte]] = @[]
  for index in 0..<37: parts.add(@[149'u8, 17, 1]) # Thirty-seven additions plus decrement/branch exceed the thirty-two-result decoder memo.
  parts.add(@[149'u8, 0, 255])
  parts.add(@[82'u8, 16, 0, 142]) # Literal minus114 targets the original block start after all thirty-eight mutations.
  parts.add(@[0'u8])
  let crowded = input(code(parts), 3)
  let completed = execute(crowded, ExecutionStepLimit(118), GasCycleLimit(10000))
  assert completed.error == StepError.None and completed.value.exit == StepExit.Panic
  same(machineInfo(completed.value.machine).value, compareSteps(crowded, 118))
  assert uint64(machineInfo(completed.value.machine).value.registers[0]) == 0
  assert uint64(machineInfo(completed.value.machine).value.registers[1]) == 111
proc threeWayPressure() =
  ## PCs0/16/32 share one bucket but have different mutations/control; rotating replacements must retain exact address tags.
  var decrement = @[149'u8, 0, 255, 255, 255, 255]
  var increment = @[149'u8, 17, 7]
  while decrement.len < 16: decrement.add(0)
  while increment.len < 16: increment.add(0) # Padding belongs only to each literal instruction's ignored operand suffix.
  let owner = code([decrement, increment, @[82'u8, 16, 0, 224], @[0'u8]])
  let source = input(owner, 5)
  let run = execute(source, ExecutionStepLimit(16), GasCycleLimit(10000))
  assert run.error == StepError.None and run.value.exit == StepExit.Panic
  same(machineInfo(run.value.machine).value, compareSteps(source, 16))
  assert uint64(machineInfo(run.value.machine).value.registers[0]) == 0
  assert uint64(machineInfo(run.value.machine).value.registers[1]) == 35
  assert uint64(machineInfo(source).value.registers[0]) == 5
  assert execute(source, ExecutionStepLimit(15), GasCycleLimit(10000)).error ==
      StepError.StepLimitExceeded

proc alternatingPrices() =
  ## Independent GP prices15/22/22 cover exact cached roots, every repeated debit and later-block simulation refusal.
  let owner = code([@[131'u8, 119, 1], @[40'u8, 5, 0, 0, 0], @[131'u8, 170, 1],
    @[83'u8, 74, 5, 0, 0, 0, 245, 255, 255, 255], @[50'u8, 2]])
  let source = input(owner, 0)
  let run = execute(source, ExecutionStepLimit(21), GasCycleLimit(25))
  assert run.error == StepError.None and run.value.exit == StepExit.Halt
  same(machineInfo(run.value.machine).value, compareSteps(source, 21, StepExit.Halt))
  let final = machineInfo(run.value.machine).value
  assert uint64(final.gas) == high(uint64)-207
  assert uint64(final.registers[7]) == 5 and uint64(final.registers[10]) == 5
  assert execute(source, ExecutionStepLimit(20), GasCycleLimit(25)).error ==
      StepError.StepLimitExceeded
  # A prior high-limit invocation must never authorize a first/later price under a new lower limit.
  assert execute(source, ExecutionStepLimit(21), GasCycleLimit(0)).error ==
      StepError.GasCycleLimitExceeded
  assert execute(source, ExecutionStepLimit(21), GasCycleLimit(18)).error ==
      StepError.GasCycleLimitExceeded
  for index in 0..<4:
    # Exact independent balances stop before mutations at primary hits, secondary hits and the terminal block.
    let balances = [36'u64, 37, 52, 185]
    let pcs = [8'u64, 0, 8, 21]
    let gas = [21'u64, 0, 0, 0]
    let additions = [1'u64, 1, 2, 5]
    let counters = [0'u64, 1, 1, 5]
    var cpu = machineInfo(source).value
    cpu.gas = MachineGas(balances[index])
    let limited = captureMachine(owner, memoryOf(source).value, cpu).value
    let stopped = execute(limited, ExecutionStepLimit(21), GasCycleLimit(25))
    assert stopped.error == StepError.None and stopped.value.exit == StepExit.OutOfGas
    var expected = cpu
    expected.pc = CodeAddress(pcs[index])
    expected.gas = MachineGas(gas[index])
    expected.registers[7] = RegisterValue(additions[index])
    expected.registers[10] = RegisterValue(counters[index])
    expected.blockCharged = false
    same(machineInfo(stopped.value.machine).value, expected)
    assert uint64(machineInfo(limited).value.gas) == balances[index]
  # Entering inside an unpaid block still charges its complete15-price prefix before the jump.
  var interior = machineInfo(source).value
  interior.pc = CodeAddress(3)
  let entered = captureMachine(owner, memoryOf(source).value, interior).value
  let completed = execute(entered, ExecutionStepLimit(20), GasCycleLimit(25))
  assert completed.error == StepError.None and completed.value.exit == StepExit.Halt
  same(machineInfo(completed.value.machine).value, compareSteps(entered, 20, StepExit.Halt))
  assert uint64(machineInfo(completed.value.machine).value.gas) == high(uint64)-207
  assert uint64(machineInfo(completed.value.machine).value.registers[7]) == 4

proc pricePressure() =
  ## Five recurrent blocks exceed four cached prices; independent pipeline witnesses are15/15/16/21/22, then terminal22.
  var parts: seq[seq[byte]] = @[]
  for count in [1, 3, 5, 7]:
    for index in 0..<count: parts.add(@[150'u8, 119,
        2]) # Dependent multiply chains produce genuinely distinct block prices.
    parts.add(@[40'u8, 5, 0, 0, 0])
  parts.add(@[131'u8, 170, 1])
  parts.add(@[83'u8, 74, 3, 0, 0, 0, 185, 255, 255, 255]) # PC71 minus71 enters the original first block.
  parts.add(@[50'u8, 2])
  let owner = code(parts)
  let base = input(owner, 0)
  var cpu = machineInfo(base).value
  cpu.registers[7] = RegisterValue(1)
  let source = captureMachine(owner, memoryOf(base).value, cpu).value
  let run = execute(source, ExecutionStepLimit(67), GasCycleLimit(25))
  assert run.error == StepError.None and run.value.exit == StepExit.Halt
  same(machineInfo(run.value.machine).value, compareSteps(source, 67, StepExit.Halt))
  let final = machineInfo(run.value.machine).value
  assert uint64(final.gas) == high(uint64)-289
  assert uint64(final.registers[7]) == (1'u64 shl 48) and uint64(final.registers[10]) == 3
  assert uint64(machineInfo(source).value.registers[7]) == 1
  assert execute(source, ExecutionStepLimit(66), GasCycleLimit(25)).error ==
      StepError.StepLimitExceeded

proc collidingPrices() =
  ## Historical eight-set collisions retain six unequal recurrent prices and exceed the three hot entries.
  var first = @[40'u8, 9, 0, 0, 0]
  while first.len < 9: first.add(0) # Ignored suffix places the first recurrent block at the independently chosen PC9.
  var parts = @[first]
  let multiplyCounts = [1, 3, 2, 1, 3]
  let jumpLengths = [18, 25, 15, 10, 12]
  for blockIndex in 0..<5:
    for index in 0..<multiplyCounts[blockIndex]: parts.add(@[150'u8, 119, 2])
    var jump = @[40'u8, byte(jumpLengths[blockIndex]), 0, 0, 0]
    while jump.len < jumpLengths[blockIndex]: jump.add(
        0) # The jump reaches exactly the next original partition, without executing ignored operand bytes.
    parts.add(jump)
  for index in 0..<5: parts.add(@[150'u8, 119, 2])
  parts.add(@[131'u8, 170, 1])
  parts.add(@[83'u8, 74, 4, 0, 0, 0, 128, 255, 255,
      255]) # PC137 minus128 reaches PC9; all six unequal blocks recur four times.
  parts.add(@[50'u8, 2])
  let owner = code(parts)
  let base = input(owner, 0)
  var cpu = machineInfo(base).value
  cpu.registers[7] = RegisterValue(1)
  let source = captureMachine(owner, memoryOf(base).value, cpu).value
  let run = execute(source, ExecutionStepLimit(90), GasCycleLimit(10000))
  assert run.error == StepError.None and run.value.exit == StepExit.Halt
  same(machineInfo(run.value.machine).value, compareSteps(source, 90, StepExit.Halt))
  assert uint64(machineInfo(run.value.machine).value.registers[7]) == 1'u64 shl 60
  assert uint64(machineInfo(run.value.machine).value.registers[10]) == 4
  same(machineInfo(source).value, cpu)
  assert execute(source, ExecutionStepLimit(89), GasCycleLimit(10000)).error ==
      StepError.StepLimitExceeded

proc largerPriceWorkingSet(blocks = 24) =
  ## Both the historical24-block case and144 recurrent blocks check exact replacement through complete public-step parity.
  assert blocks in [24, 144]
  var parts: seq[seq[byte]] = @[]
  var pc = 0
  var instructions = 0
  for blockIndex in 0..<blocks:
    for index in 0..<(1+blockIndex mod 4):
      parts.add(@[150'u8, 119, 2])
      pc += 3
      inc instructions
    parts.add(@[1'u8]) # A terminating fallthrough creates each next literal block boundary.
    inc pc
    inc instructions
  parts.add(@[149'u8, 0, 255])
  pc += 3
  let backwards = 65536-pc # Both bounded programs fit a signed two-byte displacement back to their exact PC0.
  parts.add(@[82'u8, 16, 0, byte(backwards and 255), byte(backwards shr 8)])
  parts.add(@[0'u8])
  let attempts = uint64((instructions+2)*3+1)
  let source = input(code(parts), 3)
  let run = execute(source, ExecutionStepLimit(attempts), GasCycleLimit(10000))
  assert run.error == StepError.None and run.value.exit == StepExit.Panic
  same(machineInfo(run.value.machine).value, compareSteps(source, int64(attempts)))
  assert uint64(machineInfo(source).value.registers[0]) == 3
  assert execute(source, ExecutionStepLimit(attempts-1), GasCycleLimit(10000)).error ==
      StepError.StepLimitExceeded

proc expandedPriceCollisions() =
  ## Literal starts9/64/153/208/297/352 share new set35; six unequal prices exceed both secondary ways and three recent entries.
  let starts = [9, 64, 153, 208, 297, 352]
  let multiplies = [1, 3, 2, 1, 3]
  var parts = @[@[40'u8, 9, 0, 0, 0]]
  var pc = 5
  for blockIndex in 0..<6:
    while pc < starts[blockIndex]:
      parts.add(@[0'u8]) # Unexecuted padding has explicit instruction masks, never an oversized operand partition.
      inc pc
    if blockIndex < 5:
      for index in 0..<multiplies[blockIndex]:
        parts.add(@[150'u8, 119, 2])
        pc += 3
      let distance = starts[blockIndex+1]-pc
      parts.add(@[40'u8, byte(distance), 0, 0, 0])
      pc += 5
  for index in 0..<5: parts.add(@[150'u8, 119, 2])
  pc += 15
  parts.add(@[131'u8, 170, 1])
  pc += 3
  let backwards = 0x100000000'u64-uint64(pc-starts[0])
  parts.add(@[83'u8, 74, 4, 0, 0, 0, byte(backwards and 255), byte((backwards shr 8) and 255),
    byte((backwards shr 16) and 255), byte(backwards shr 24)])
  parts.add(@[50'u8, 2])
  let owner = code(parts)
  let base = input(owner, 0)
  var cpu = machineInfo(base).value
  cpu.registers[7] = RegisterValue(1)
  let source = captureMachine(owner, memoryOf(base).value, cpu).value
  let run = execute(source, ExecutionStepLimit(90), GasCycleLimit(10000))
  assert run.error == StepError.None and run.value.exit == StepExit.Halt
  same(machineInfo(run.value.machine).value, compareSteps(source, 90, StepExit.Halt))
  assert uint64(machineInfo(run.value.machine).value.registers[7]) == 1'u64 shl 60
  assert uint64(machineInfo(run.value.machine).value.registers[10]) == 4
  same(machineInfo(source).value, cpu)
  assert execute(source, ExecutionStepLimit(89), GasCycleLimit(10000)).error ==
      StepError.StepLimitExceeded

proc denseSource(delta = 1, hosted = false): Machine =
  ##4500 distinct additions exceed both cache capacities; ten rounds cross the32768-successful-miss allocation threshold.
  assert delta in [1, 8]
  var parts: seq[seq[byte]] = @[]
  for index in 0..<4500:
    parts.add(@[149'u8, 17, byte(delta+index mod 7)]) # Different literal immediates expose incorrect full-PC tags.
  parts.add(@[149'u8, 0, 255])
  let backwards = 65536-13503 # The original conditional at PC13503 returns exactly to the first opcode.
  parts.add(@[82'u8, 16, 0, byte(backwards and 255), byte(backwards shr 8)])
  if hosted:
    # A continued host reply returns through the same dense working set; nested execution uses another program at identical PCs.
    parts.add(@[10'u8, 1])
    let offset = 0x100000000'u64-13510
    parts.add(@[40'u8, byte(offset and 255), byte((offset shr 8) and 255),
      byte((offset shr 16) and 255), byte(offset shr 24)])
  else:
    parts.add(@[0'u8]) # Guest-only callers retain a literal terminal trap after the ten completed rounds.
  input(code(parts), 10)

proc densePolicies(source: Machine): tuple[plan: GasPlan, memo: GasMemo] =
  ## Both fixed-source policies admit the independently bounded large program; no partial policy is extracted on refusal.
  let plan = newGasPlan(programOf(source).value, GasPlanLimits(blocks: GasPlanBlockLimit(8),
    bytes: GasPlanByteLimit(262144), cycles: GasCycleLimit(100000)))
  let memo = newGasMemo(programOf(source).value, GasMemoLimits(bytes: GasMemoByteLimit(262144),
    cycles: GasCycleLimit(100000)))
  assert plan.error == GasPlanError.None and memo.error == GasMemoError.None
  (plan.value, memo.value)

proc denseRun(source: Machine, mode: int, plan: GasPlan, memo: GasMemo,
    attempts = 45021'u64): StepResult =
  ##4500 additions, one decrement and one branch per round, plus a final trap, define the exact attempt bound.
  case mode
  of 0: execute(source, ExecutionStepLimit(attempts), GasCycleLimit(100000))
  of 1: execute(source, ExecutionStepLimit(attempts), plan)
  else: execute(source, ExecutionStepLimit(attempts), memo)

proc denseGuestPressure() =
  ## Cold/warm policies, pressure beyond4128 positions and local refusals retain complete single-step CPU/gas parity.
  let source = denseSource()
  let original = machineInfo(source).value
  let expected = compareSteps(source, 45021, StepExit.Panic, GasCycleLimit(100000))
  assert uint64(expected.registers[0]) == 0 and uint64(expected.registers[1]) == 179970
  let policies = densePolicies(source)
  for mode in 0..<3:
    for repetition in 0..<2:
      # A fresh invocation starts empty even when complete/lazy source-owned pricing facts are reused.
      let done = denseRun(source, mode, policies.plan, policies.memo)
      assert done.error == StepError.None and done.value.exit == StepExit.Panic
      same(machineInfo(done.value.machine).value, expected)
      same(machineInfo(source).value, original)
    assert denseRun(source, mode, policies.plan, policies.memo, 45020).error ==
        StepError.StepLimitExceeded
  var shortCpu = original
  shortCpu.gas = MachineGas(1)
  let short = captureMachine(programOf(source).value, memoryOf(source).value, shortCpu).value
  for mode in 0..<3:
    # Unaffordability still precedes the first register mutation regardless of reusable decoder facts in an earlier invocation.
    let done = denseRun(short, mode, policies.plan, policies.memo)
    assert done.error == StepError.None and done.value.exit == StepExit.OutOfGas
    same(machineInfo(done.value.machine).value, shortCpu)

  # Repeated defaults/source aliases cannot retain the bounded decoded spill beyond a completed invocation.
  let occupied = getOccupiedMem()
  for repetition in 0..<4:
    for mode in 0..<3:
      let done = denseRun(source, mode, policies.plan, policies.memo)
      assert done.error == StepError.None
      same(machineInfo(done.value.machine).value, expected)
  assert getOccupiedMem() == occupied

type DenseContext = object ## Expected CPU values and a separately owned nested source never grant access to either private decoder cache.
  expected: array[2, MachineInfo]
  nestedExpected: MachineInfo
  nested: Machine
  calls: int
  refuse: bool

proc denseReply(context: var DenseContext, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## Both dense invocations own spills at identical PCs; the outer program must regain its original operands after continuation.
  assert context.calls < 2 and uint64(stopped.hostCall) == 1
  let cpu = machineInfo(stopped.machine).value
  same(cpu, context.expected[context.calls])
  let nested = execute(context.nested, ExecutionStepLimit(45021), GasCycleLimit(100000))
  assert nested.error == StepError.None and nested.value.exit == StepExit.Panic
  same(machineInfo(nested.value.machine).value, context.nestedExpected)
  assert uint64(machineInfo(context.nested).value.registers[0]) == 10
  inc context.calls
  var registers = cpu.registers
  if context.calls == 1:
    registers[0] = RegisterValue(10) # Re-enter the original dense guest for another ten rounds.
  HostResponse(action: (if context.calls == 1: HostAction.Continue else: HostAction.Panic),
    gas: cpu.gas, registers: registers, memory: memoryOf(stopped.machine).value)

proc denseReplyFallible(context: var DenseContext, stopped: StepOutcome): HostResult[
    Reason] {.raises: [].} =
  ## A typed refusal after the second nested run retains context effects and publishes no guest prefix.
  let response = denseReply(context, stopped)
  if context.refuse and context.calls == 2: return hostFailure(Reason.Refused)
  hostSuccess[Reason](response)

proc denseHostPressure() =
  ## Exact90043 attempts cover two ten-round dense passes, the first host continuation/jump and the second terminal callback.
  let source = denseSource(hosted = true)
  let nested = denseSource(8)
  let first = compareSteps(source, 45021, StepExit.Host, GasCycleLimit(100000))
  var posterior = first
  posterior.pc = CodeAddress(13510)
  posterior.registers[0] = RegisterValue(10)
  let resumed = captureMachine(programOf(source).value, memoryOf(source).value, posterior).value
  let second = compareSteps(resumed, 45022, StepExit.Host, GasCycleLimit(100000))
  let nestedExpected = compareSteps(nested, 45021, StepExit.Panic, GasCycleLimit(100000))
  assert uint64(second.registers[1]) == 359940 and uint64(nestedExpected.registers[1]) == 494970
  let policies = densePolicies(source)
  for mode in 0..<3:
    var context = DenseContext(expected: [first, second], nestedExpected: nestedExpected,
      nested: nested, calls: 0, refuse: false)
    let ordinary = case mode
      of 0: executeWithHost(source, context, denseReply, ExecutionStepLimit(90043), HostCallLimit(
          2), GasCycleLimit(100000))
      of 1: executeWithHost(source, context, denseReply, ExecutionStepLimit(90043), HostCallLimit(
          2), policies.plan)
      else: executeWithHost(source, context, denseReply, ExecutionStepLimit(90043), HostCallLimit(
          2), policies.memo)
    assert ordinary.error == StepError.None and ordinary.value.exit == StepExit.Panic and
        context.calls == 2
    same(machineInfo(ordinary.value.machine).value, second)
    context.calls = 0
    let fallible = case mode
      of 0: executeWithHost(source, context, denseReplyFallible, ExecutionStepLimit(90043),
          HostCallLimit(2), GasCycleLimit(100000))
      of 1: executeWithHost(source, context, denseReplyFallible, ExecutionStepLimit(90043),
          HostCallLimit(2), policies.plan)
      else: executeWithHost(source, context, denseReplyFallible, ExecutionStepLimit(90043),
          HostCallLimit(2), policies.memo)
    assert fallible.error == HostExecutionError.None and fallible.value.exit == StepExit.Panic and
        context.calls == 2
    same(machineInfo(fallible.value.machine).value, second)
    context.calls = 0
    context.refuse = true
    let refused = case mode
      of 0: executeWithHost(source, context, denseReplyFallible, ExecutionStepLimit(90043),
          HostCallLimit(2), GasCycleLimit(100000))
      of 1: executeWithHost(source, context, denseReplyFallible, ExecutionStepLimit(90043),
          HostCallLimit(2), policies.plan)
      else: executeWithHost(source, context, denseReplyFallible, ExecutionStepLimit(90043),
          HostCallLimit(2), policies.memo)
    assert refused.error == HostExecutionError.HostFailure and refused.hostError ==
        Reason.Refused and context.calls == 2
    context.calls = 0
    context.refuse = false
    let short = case mode
      of 0: executeWithHost(source, context, denseReply, ExecutionStepLimit(90042), HostCallLimit(
          2), GasCycleLimit(100000))
      of 1: executeWithHost(source, context, denseReply, ExecutionStepLimit(90042), HostCallLimit(
          2), policies.plan)
      else: executeWithHost(source, context, denseReply, ExecutionStepLimit(90042), HostCallLimit(
          2), policies.memo)
    assert short.error == StepError.StepLimitExceeded and context.calls == 1
  assert uint64(machineInfo(source).value.registers[0]) == 10 and uint64(machineInfo(
      source).value.registers[1]) == 0

proc denseArc(source: Machine, plan: GasPlan, expected: MachineInfo) =
  ## Each complete-plan invocation creates and destroys its own sustained-pressure decoder spill; only copied CPU values survive.
  let done = execute(source, ExecutionStepLimit(45021), plan)
  assert done.error == StepError.None and done.value.exit == StepExit.Panic
  same(machineInfo(done.value.machine).value, expected)

proc respond(context: var Context, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## Nested execution uses different operands at the outer continuation PC; it must never overwrite that invocation's cached instruction.
  assert stopped.exit == StepExit.Host and context.calls < 2
  let cpu = machineInfo(stopped.machine).value
  assert uint64(stopped.hostCall) == uint64(5+context.calls)
  assert uint64(cpu.pc) == (if context.calls == 0: 3'u64 else: 8'u64)
  assert uint64(cpu.registers[0]) == uint64(7+context.calls)
  let nested = execute(context.nested, ExecutionStepLimit(7), GasCycleLimit(0))
  assert nested.error == StepError.None and nested.value.exit == StepExit.Panic
  assert uint64(machineInfo(nested.value.machine).value.registers[0]) == 99
  assert uint64(machineInfo(context.nested).value.registers[0]) == 0
  inc context.calls
  HostResponse(action: HostAction.Continue, gas: cpu.gas, registers: cpu.registers,
      memory: memoryOf(stopped.machine).value)
proc respondFallible(context: var Context, stopped: StepOutcome): HostResult[Reason] {.raises: [].} =
  ## Successful and refusing host adapters share the same invocation cache lifetime without carrying a machine on local failure.
  let response = respond(context, stopped)
  if context.refuse and context.calls == 2: return hostFailure(Reason.Refused)
  hostSuccess[Reason](response)
proc hosts() =
  ## Reentrant calls, ordinary/fallible host resumptions and separate cold invocations preserve exact literal program identities.
  let nested = input(code([@[2'u8], @[2'u8], @[2'u8], @[2'u8], @[2'u8], @[51'u8, 0, 99], @[0'u8]]), 0, true)
  let source = input(code([@[51'u8, 0, 7], @[10'u8, 5], @[149'u8, 0, 1], @[10'u8, 6], @[50'u8, 2]]), 0)
  var context = Context(nested: nested, calls: 0, refuse: false)
  let ordinary = executeWithHost(source, context, respond, ExecutionStepLimit(5), HostCallLimit(2),
      GasCycleLimit(10000))
  assert ordinary.error == StepError.None and ordinary.value.exit == StepExit.Halt and
      context.calls == 2
  assert uint64(machineInfo(ordinary.value.machine).value.registers[0]) == 8
  context = Context(nested: nested, calls: 0, refuse: false)
  let fallible = executeWithHost(source, context, respondFallible, ExecutionStepLimit(5),
      HostCallLimit(2), GasCycleLimit(10000))
  assert fallible.error == HostExecutionError.None and fallible.value.exit == StepExit.Halt and
      context.calls == 2
  same(machineInfo(fallible.value.machine).value, machineInfo(ordinary.value.machine).value)
  context = Context(nested: nested, calls: 0, refuse: true)
  let refused = executeWithHost(source, context, respondFallible, ExecutionStepLimit(5),
      HostCallLimit(2), GasCycleLimit(10000))
  assert refused.error == HostExecutionError.HostFailure and refused.hostError == Reason.Refused and
      context.calls == 2
  context = Context(nested: nested, calls: 0, refuse: false)
  assert executeWithHost(source, context, respond, ExecutionStepLimit(5), HostCallLimit(1),
      GasCycleLimit(10000)).error == StepError.HostCallLimitExceeded
  assert context.calls == 1
  assert uint64(machineInfo(source).value.registers[0]) == 0
  for literal in [1'u8, 42, 99]:
    let fresh = input(code([@[51'u8, 0, literal], @[0'u8]]), 0, true)
    let run = execute(fresh, ExecutionStepLimit(2), GasCycleLimit(0))
    assert run.error == StepError.None and uint64(machineInfo(run.value.machine).value.registers[
        0]) == uint64(literal)
proc staticConditions() =
  ## Every conditional family must reject a bad destination even when its predicate would select the valid successor.
  for opcode in [81'u8, 82, 83, 84, 85, 86, 87, 88, 89, 90, 170, 171, 172, 173, 174, 175]:
    for count in [0'u64, 1, high(uint64)]:
      let descriptor = if opcode >= 170: 16'u8 else: 0'u8
      let owner = code([@[opcode, descriptor, 1, 0, 0, 0], @[
          0'u8]]) # PC1 is an unmarked operand, while the fallthrough is a valid block.
      let source = input(owner, count, true)
      let once = stepOnce(source, GasCycleLimit(0))
      let run = execute(source, ExecutionStepLimit(1), GasCycleLimit(0))
      assert once.error == StepError.None and once.value.exit == StepExit.Panic
      assert run.error == StepError.None and run.value.exit == StepExit.Panic
      same(machineInfo(once.value.machine).value, machineInfo(run.value.machine).value)
      assert uint64(machineInfo(source).value.registers[0]) == count
      var unpaid = machineInfo(source).value
      unpaid.blockCharged = false
      unpaid.gas = MachineGas(0)
      let empty = captureMachine(owner, memoryOf(source).value, unpaid).value
      let shortage = execute(empty, ExecutionStepLimit(1), GasCycleLimit(1000))
      assert shortage.error == StepError.None and shortage.value.exit == StepExit.OutOfGas
      same(machineInfo(shortage.value.machine).value,
          unpaid) # Static facts never move invalid-target panic ahead of affordability.
  # A static load-and-jump still commits its explicit register mutation when the target panics.
  let owner = code([@[80'u8, 0, 1, 0, 0, 0], @[0'u8]])
  let source = input(owner, 99, true)
  let run = execute(source, ExecutionStepLimit(1), GasCycleLimit(0))
  assert run.error == StepError.None and run.value.exit == StepExit.Panic
  assert uint64(machineInfo(run.value.machine).value.registers[0]) == 0
  assert uint64(machineInfo(source).value.registers[0]) == 99

proc finalFallthrough() =
  ## Paper permits a final conditional; both branches retain the specified panic when either control successor is absent.
  var owner = code([@[82'u8, 16, 0, 0]])
  let final = instruction(owner, CodeAddress(0))
  assert final.error == ProgramError.None and not instructionHasFallthrough(final)
  var extracted = final.value
  extracted.address = CodeAddress(99)
  extracted.skip = 0
  extracted.opcode = 0 # Mutable public operand copies cannot modify or rebind the sealed chain fact.
  assert not instructionHasFallthrough(final)
  for count in [0'u64, 1]:
    let source = input(owner, count, true)
    let once = stepOnce(source, GasCycleLimit(0))
    let run = execute(source, ExecutionStepLimit(1), GasCycleLimit(0))
    assert once.error == StepError.None and once.value.exit == StepExit.Panic, "final conditional single step"
    assert run.error == StepError.None and run.value.exit == StepExit.Panic, "final conditional execute"
    same(machineInfo(once.value.machine).value, machineInfo(run.value.machine).value)
    assert execute(source, ExecutionStepLimit(0), GasCycleLimit(0)).error ==
        StepError.StepLimitExceeded
    assert uint64(machineInfo(source).value.registers[0]) == count
    var unpaid = machineInfo(source).value
    unpaid.gas = MachineGas(0)
    unpaid.blockCharged = false
    let empty = captureMachine(owner, memoryOf(source).value, unpaid).value
    let shortage = execute(empty, ExecutionStepLimit(1), GasCycleLimit(100))
    assert shortage.error == StepError.None and shortage.value.exit == StepExit.OutOfGas
    same(machineInfo(shortage.value.machine).value,
        unpaid) # Unaffordability precedes any missing-successor refusal.
  let ordinary = code([@[51'u8, 0, 7], @[0'u8]])
  let first = instruction(ordinary, CodeAddress(0))
  let retained = first
  assert instructionHasFallthrough(first)
  owner = default(Program)
  assert not instructionHasFallthrough(final) and instructionHasFallthrough(retained)

type
  JumpContext = object ## Reentrant guests use another immutable jump table while the outer invocation retains exact target tags.
    nested: Machine
    previous: RegisterFile
    calls, count, expectedHost: int
    terminal: uint64

proc jumpReply(context: var JumpContext, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## Independently known block prices and alternating host identities expose wrong-target hits before terminal normalization.
  let cpu = machineInfo(stopped.machine).value
  assert uint64(stopped.hostCall) == uint64(context.expectedHost)
  assert uint64(cpu.pc) == (if context.expectedHost == 1: 0'u64 else: 4'u64)
  assert uint64(cpu.gas) == uint64((context.count-context.calls-1)*100+7)
  assert cpu.blockCharged and uint64(cpu.gasDeficit) == 0
  for i in 0..<13: assert uint64(cpu.registers[i]) == uint64(context.previous[i])
  let nested = execute(context.nested, ExecutionStepLimit(2), GasCycleLimit(103))
  assert nested.error == StepError.None and nested.value.exit == StepExit.Panic
  same(machineInfo(nested.value.machine).value, compareSteps(context.nested, 2))
  assert uint64(machineInfo(context.nested).value.pc) == 0
  inc context.calls
  var registers = cpu.registers
  if context.calls == context.count:
    registers[8] = RegisterValue(0x1234567800000000'u64 or context.terminal)
  else:
    # Ordinals0/4 collide; repeated hits and ordinal3 exercise separate slots. Upper bits are discarded by the existing address rule.
    let indices = [0'u64, 0, 4, 4, 0, 4, 3, 3]
    let index = indices[(context.calls-1) mod indices.len]
    registers[8] = RegisterValue(0x1234567800000000'u64 or (2*(index+1)))
    context.expectedHost = if index == 0: 1 else: 2
  context.previous = registers
  HostResponse(action: HostAction.Continue, gas: cpu.gas, registers: registers,
    memory: memoryOf(stopped.machine).value)

proc jumpReplyFallible(context: var JumpContext, stopped: StepOutcome): HostResult[
    Reason] {.raises: [].} =
  ## Both public host callback forms must retain the same program-local facts and synchronous reentry isolation.
  hostSuccess[Reason](jumpReply(context, stopped))

proc dynamicTargets(count = 64, full = true) =
  ## Literal table entries include colliding valid blocks, an operand byte, an out-of-code target and an absent ordinal.
  let decoded = decodeProgram(@[5'u8, 1, 8, 0, 1, 255, 4, 4, 10, 1, 50, 8, 10, 2, 50, 8, 0x55],
    CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(5))
  let other = decodeProgram(@[1'u8, 1, 3, 2, 50, 8, 0, 5], CodeAddress(0),
    ProgramByteLimit(64), JumpCountLimit(1))
  assert decoded.error == ProgramError.None and other.error == ProgramError.None
  let owner = decoded.value
  var original = default(RegisterFile)
  for i in 0..<13: original[i] = RegisterValue(uint64(500+i))
  original[8] = RegisterValue(2)
  let empty = captureMemory([], PageLimit(0)).value
  let cpu = MachineInfo(pc: CodeAddress(0), gas: MachineGas(uint64(count*100+7)),
    registers: original, blockCharged: false)
  let source = captureMachine(owner, empty, cpu).value
  var nestedCpu = cpu
  nestedCpu.gas = MachineGas(1000)
  let nested = captureMachine(other.value, empty, nestedCpu).value
  let prepared = newGasPlan(owner, GasPlanLimits(blocks: GasPlanBlockLimit(2),
    bytes: GasPlanByteLimit(64), cycles: GasCycleLimit(103)))
  let learned = newGasMemo(owner, GasMemoLimits(bytes: GasMemoByteLimit(64), cycles: GasCycleLimit(103)))
  assert prepared.error == GasPlanError.None and learned.error == GasMemoError.None
  let plan = prepared.value
  let memo = learned.value
  # Independent pipeline simulation gives100gas/103cycles for each host-plus-indirect-jump block.
  assert uint64(blockGas(owner, CodeAddress(0), GasCycleLimit(103)).value) == 100
  assert uint64(blockGas(owner, CodeAddress(4), GasCycleLimit(103)).value) == 100
  for policy in 0..<(if full: 3 else: 1):
    for terminal in [0xffff0000'u64, 4, 6, 18, 0, 3]:
      for fallible in [false, true]:
        var context = JumpContext(nested: nested, previous: original,
          calls: 0, count: count, expectedHost: 1, terminal: terminal)
        var outcome = default(StepOutcome)
        template run(selected: untyped) =
          # Static selection preserves the public overload and distinct failure result types.
          if fallible:
            let stopped = executeWithHost(source, context, jumpReplyFallible, ExecutionStepLimit(
                uint64(count*2)),
              HostCallLimit(uint64(count)), selected)
            assert stopped.error == HostExecutionError.None
            outcome = stopped.value
          else:
            let stopped = executeWithHost(source, context, jumpReply, ExecutionStepLimit(uint64(
                count*2)),
              HostCallLimit(uint64(count)), selected)
            assert stopped.error == StepError.None
            outcome = stopped.value
        case policy
        of 0: run(GasCycleLimit(103)) # Dynamic simulation still checks affordability at every block visit.
        of 1: run(plan) # Complete pricing does not change target-cache identity.
        else: run(memo) # Lazy prices may survive calls; target facts must not.
        assert context.calls == count
        assert outcome.exit == (if terminal == 0xffff0000'u64: StepExit.Halt else: StepExit.Panic)
        var expected = cpu
        expected.gas = MachineGas(7)
        expected.blockCharged = true
        expected.registers = context.previous
        same(machineInfo(outcome.machine).value, expected)
        same(machineInfo(source).value, cpu)
  # One-less cycle limit refuses pricing before any callback or target cache lookup.
  var context = JumpContext(nested: nested, previous: original,
    calls: 0, count: count, expectedHost: 1, terminal: 0xffff0000'u64)
  let refused = executeWithHost(source, context, jumpReply, ExecutionStepLimit(uint64(count*2)),
    HostCallLimit(uint64(count)), GasCycleLimit(102))
  assert refused.error == StepError.GasCycleLimitExceeded and context.calls == 0


proc controlOwner(opcode: byte, alias = false, tableTarget = 7'u8): Program =
  ## Seven-byte literal partitions make all successful taken/fallthrough destinations PC7; table contents stay independently authored.
  if opcode == 50 or opcode == 180:
    var wire = @[1'u8, 1, 8, tableTarget]
    let part = if opcode == 50: @[50'u8, 8, 0, 0, 0, 0, 0]
      else: @[180'u8, byte(if alias: 0x88 else: 0x80), 1, 99, 0, 0, 0]
    for octet in part: wire.add(octet)
    wire.add(0) # The only following instruction is a marked trap at PC7.
    wire.add(0x81)
    let parsed = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(1))
    assert parsed.error == ProgramError.None
    return parsed.value
  let part = if opcode == 1: @[1'u8, 0, 0, 0, 0, 0, 0]
    elif opcode == 40: @[40'u8, 7, 0, 0, 0, 0, 0]
    else: @[opcode, byte(if opcode >= 170: 16 else: 0), 7, 0, 0, 0, 0]
  code([part, @[0'u8]])

proc controlRun(source: Machine, mode: int, attempts: uint64, plan: GasPlan,
    memo: GasMemo): StepResult =
  ## Exercise the actual dynamic, complete and lazy public overloads under one shared instruction-attempt contract.
  case mode
  of 0: execute(source, ExecutionStepLimit(attempts), GasCycleLimit(25))
  of 1: execute(source, ExecutionStepLimit(attempts), plan)
  else: execute(source, ExecutionStepLimit(attempts), memo)

proc controlSuccessors() =
  ## Every nontrapping control family must select a real instruction before a local budget can stop the next attempt.
  let memory = captureMemory([], PageLimit(0)).value
  for opcode in [1'u8, 40, 50, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90,
      170, 171, 172, 173, 174, 175, 180]:
    for alias in [false, true]:
      if alias and opcode != 180: continue # Only load-and-jump has an explicit destination that can alias its target source.
      let owner = controlOwner(opcode, alias)
      let prepared = newGasPlan(owner, GasPlanLimits(blocks: GasPlanBlockLimit(2),
        bytes: GasPlanByteLimit(64), cycles: GasCycleLimit(25)))
      let learned = newGasMemo(owner, GasMemoLimits(bytes: GasMemoByteLimit(64),
          cycles: GasCycleLimit(25)))
      assert prepared.error == GasPlanError.None and learned.error == GasMemoError.None
      let plan = prepared.value
      let memo = learned.value
      # Independent pipeline simulation of these exact raw partitions gives2/15/22/1 gas; the following trap costs2.
      let price = if opcode == 1: 2'u64 elif opcode == 40 or opcode == 80: 15'u64
        elif opcode == 50 or opcode == 180: 22'u64 else: 1'u64
      for word in [0'u64, 1, high(uint64), 0x8000000000000000'u64]:
        for prepaid in [false, true]:
          var registers = default(RegisterFile)
          for i in 0..<13: registers[i] = RegisterValue(uint64(500+i))
          registers[0] = RegisterValue(word)
          registers[1] = RegisterValue(not word)
          if opcode == 50 or opcode == 180: registers[8] = RegisterValue(0x1234567800000002'u64)
          let cpu = MachineInfo(pc: CodeAddress(0), gas: MachineGas(29+(
              if prepaid: 0'u64 else: price)),
            gasDeficit: GasDeficit(0), blockCharged: prepaid, registers: registers)
          let source = captureMachine(owner, memory, cpu).value
          var expected = cpu
          expected.pc = CodeAddress(7)
          expected.gas = MachineGas(29)
          expected.blockCharged = false
          if opcode == 80: expected.registers[0] = RegisterValue(0)
          elif opcode == 180: expected.registers[if alias: 8 else: 0] = RegisterValue(99)
          for planned in [false, true]:
            # Public stepping still publishes and validates the complete literal successor snapshot.
            let once = if planned: stepOnce(source, plan) else: stepOnce(source, GasCycleLimit(25))
            assert once.error == StepError.None and once.value.exit == StepExit.Continued
            same(machineInfo(once.value.machine).value, expected)
            assert instructionOpcode(owner, expected.pc).error == ProgramError.None
          for mode in 0..<3:
            # One attempt refuses locally; two attempts execute the selected trap with its independent price and final PC normalization.
            assert controlRun(source, mode, 1, plan, memo).error == StepError.StepLimitExceeded
            let completed = controlRun(source, mode, 2, plan, memo)
            assert completed.error == StepError.None and completed.value.exit == StepExit.Panic
            var final = expected
            final.pc = CodeAddress(0)
            final.gas = MachineGas(27)
            final.blockCharged = true
            same(machineInfo(completed.value.machine).value, final)
            same(machineInfo(source).value, cpu)
  for alias in [false, true]:
    for failure in 0..<6:
      # Operand/out-of-code/missing targets, zero/odd addresses and halt precedence retain the load-and-jump register mutation.
      let tableTarget = if failure == 0: 1'u8 elif failure == 1: 8'u8 else: 7'u8
      let addresses = [2'u64, 2, 4, 0, 3, 0xffff0000'u64]
      let owner = controlOwner(180, alias, tableTarget)
      let prepared = newGasPlan(owner, GasPlanLimits(blocks: GasPlanBlockLimit(2),
        bytes: GasPlanByteLimit(64), cycles: GasCycleLimit(25)))
      let learned = newGasMemo(owner, GasMemoLimits(bytes: GasMemoByteLimit(64),
          cycles: GasCycleLimit(25)))
      assert prepared.error == GasPlanError.None and learned.error == GasMemoError.None
      let plan = prepared.value
      let memo = learned.value
      for prepaid in [false, true]:
        var registers = default(RegisterFile)
        for i in 0..<13: registers[i] = RegisterValue(uint64(900+i))
        registers[8] = RegisterValue(0x1234567800000000'u64 or addresses[failure])
        let cpu = MachineInfo(pc: CodeAddress(0), gas: MachineGas(if prepaid: 7'u64 else: 29'u64),
          gasDeficit: GasDeficit(0), blockCharged: prepaid, registers: registers)
        let source = captureMachine(owner, memory, cpu).value
        var expected = cpu
        expected.gas = MachineGas(7)
        expected.blockCharged = true
        expected.registers[if alias: 8 else: 0] = RegisterValue(99)
        for mode in 0..<3:
          let stopped = controlRun(source, mode, 1, plan, memo)
          assert stopped.error == StepError.None
          assert stopped.value.exit == (if failure == 5: StepExit.Halt else: StepExit.Panic)
          same(machineInfo(stopped.value.machine).value, expected)
          same(machineInfo(source).value, cpu)
          var shortage = cpu
          shortage.gas = MachineGas(21)
          shortage.blockCharged = false
          let poor = captureMachine(owner, memory, shortage).value
          let refused = controlRun(poor, mode, 1, plan, memo)
          assert refused.error == StepError.None and refused.value.exit == StepExit.OutOfGas
          same(machineInfo(refused.value.machine).value, shortage)


proc absentControlSuccessors() =
  ## A valid taken target cannot authorize an absent conditional fallthrough; unconditional back edges remain executable.
  for opcode in [1'u8, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 170, 171, 172, 173, 174, 175]:
    let owner = code([@[opcode, byte(if opcode >= 170: 16 else: 0), 0, 0, 0, 0, 0]])
    let decoded = instruction(owner, CodeAddress(0))
    assert decoded.error == ProgramError.None and not instructionHasFallthrough(decoded)
    let prepared = newGasPlan(owner, GasPlanLimits(blocks: GasPlanBlockLimit(1),
      bytes: GasPlanByteLimit(64), cycles: GasCycleLimit(25)))
    let learned = newGasMemo(owner, GasMemoLimits(bytes: GasMemoByteLimit(64),
        cycles: GasCycleLimit(25)))
    assert prepared.error == GasPlanError.None and learned.error == GasMemoError.None
    for word in [0'u64, 1, high(uint64), 0x8000000000000000'u64]:
      for prepaid in [false, true]:
        # Independent single-instruction prices are two for fallthrough and one for every conditional.
        let price = if opcode == 1: 2'u64 else: 1'u64
        let original = input(owner, word, prepaid)
        var cpu = machineInfo(original).value
        cpu.gas = MachineGas(7+(if prepaid: 0'u64 else: price))
        let source = captureMachine(owner, memoryOf(original).value, cpu).value
        var expected = cpu
        expected.gas = MachineGas(7)
        expected.blockCharged = true
        for mode in 0..<3:
          # Missing successors panic after charging regardless of the predicate, preserving the causing PC and every register.
          let stopped = controlRun(source, mode, 1, prepared.value, learned.value)
          assert stopped.error == StepError.None and stopped.value.exit == StepExit.Panic
          same(machineInfo(stopped.value.machine).value, expected)
          same(machineInfo(source).value, cpu)
  let loop = code([@[40'u8, 0]])
  let prepared = newGasPlan(loop, GasPlanLimits(blocks: GasPlanBlockLimit(1),
    bytes: GasPlanByteLimit(64), cycles: GasCycleLimit(25)))
  let learned = newGasMemo(loop, GasMemoLimits(bytes: GasMemoByteLimit(64), cycles: GasCycleLimit(25)))
  assert prepared.error == GasPlanError.None and learned.error == GasMemoError.None
  let original = input(loop, 99)
  var cpu = machineInfo(original).value
  cpu.gas = MachineGas(37)
  let source = captureMachine(loop, memoryOf(original).value, cpu).value
  for mode in 0..<3:
    # A final unconditional self-jump needs no sequential successor and pays again on each completed back edge.
    assert controlRun(source, mode, 2, prepared.value, learned.value).error ==
        StepError.StepLimitExceeded
    let stopped = controlRun(source, mode, 3, prepared.value, learned.value)
    assert stopped.error == StepError.None and stopped.value.exit == StepExit.OutOfGas
    var expected = cpu
    expected.gas = MachineGas(7)
    same(machineInfo(stopped.value.machine).value, expected)
    same(machineInfo(source).value, cpu)

denseGuestPressure()
denseHostPressure()
let denseOccupied = getOccupiedMem()
for repetition in 0..<4: denseHostPressure()
assert getOccupiedMem() == denseOccupied
controlSuccessors()
absentControlSuccessors()

dynamicTargets()
collisions()
threeWayPressure()
alternatingPrices()
pricePressure()
collidingPrices()
largerPriceWorkingSet()
largerPriceWorkingSet(144)
expandedPriceCollisions()
staticConditions()
hosts()
finalFallthrough()
let denseArcSource = denseSource()
let denseArcPlan = densePolicies(denseArcSource).plan
let denseArcExpected = compareSteps(denseArcSource, 45021, StepExit.Panic, GasCycleLimit(100000))
denseArc(denseArcSource, denseArcPlan, denseArcExpected)
let before = getOccupiedMem()
for cycle in 0..<1000:
  denseArc(denseArcSource, denseArcPlan, denseArcExpected)
  collisions()
  threeWayPressure()
  alternatingPrices()
  pricePressure()
  collidingPrices()
  finalFallthrough()
  dynamicTargets(8, false)
  hosts() # Both bounded memos and all observable/nested snapshot owners retire after each complete invocation group.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_execution_cache", 1000, before, after)
echo "PVM invocation decoder cache passed"
echo "ARC_RELEASE cycles=1000 unchanged"
