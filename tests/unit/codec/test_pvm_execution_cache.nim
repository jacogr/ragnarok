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
  assert bytes.len > 0 and bytes.len < 4096
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
  let captured = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(8192), JumpCountLimit(0))
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
proc compareSteps(source: Machine, attempts: int, terminal = StepExit.Panic): MachineInfo =
  ## Public single-step execution never uses the invocation cache; its complete trace independently checks composition and exit normalization.
  assert attempts > 0
  result = default(MachineInfo) # Initialize the copied result even before the bounded positive trace is traversed.
  var current = source
  for index in 0..<attempts:
    let once = stepOnce(current, GasCycleLimit(10000))
    assert once.error == StepError.None
    if index+1 == attempts:
      assert once.value.exit == terminal
      result = machineInfo(once.value.machine).value
      result.pc = CodeAddress(0) # Outer Psi normalizes final Panic/Halt while retaining all posterior CPU values.
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
  ## Six literal recurrent starts9/30/64/85/98/119 share set4 and exceed both the three hot entries and two secondary ways.
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

proc largerPriceWorkingSet() =
  ## Twenty-four recurrent blocks exceed all twenty retained price slots; full public-step CPU/gas parity survives bounded replacement.
  var parts: seq[seq[byte]] = @[]
  for blockIndex in 0..<24:
    for index in 0..<(1+blockIndex mod 4): parts.add(@[150'u8, 119, 2])
    parts.add(@[1'u8]) # A terminating fallthrough creates each next literal block boundary.
  parts.add(@[149'u8, 0, 255])
  parts.add(@[82'u8, 16, 0, 49, 255]) # PC207 minus207 returns to PC0 with a signed two-byte displacement.
  parts.add(@[0'u8])
  let source = input(code(parts), 3)
  let run = execute(source, ExecutionStepLimit(259), GasCycleLimit(10000))
  assert run.error == StepError.None and run.value.exit == StepExit.Panic
  same(machineInfo(run.value.machine).value, compareSteps(source, 259))
  assert uint64(machineInfo(source).value.registers[0]) == 3
  assert execute(source, ExecutionStepLimit(258), GasCycleLimit(10000)).error ==
      StepError.StepLimitExceeded

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

dynamicTargets()
collisions()
threeWayPressure()
alternatingPrices()
pricePressure()
collidingPrices()
largerPriceWorkingSet()
staticConditions()
hosts()
finalFallthrough()
let before = getOccupiedMem()
for cycle in 0..<1000:
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
