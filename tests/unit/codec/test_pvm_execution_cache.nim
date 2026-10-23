# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Invocation-local decoded operands survive collisions, capacity pressure and host resumptions without crossing programs or callback nesting.
# @@Verification={"arc": "pvm_execution_cache_arc_release"}
import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, gas, step]
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
  assert bytes.len > 0 and bytes.len < 128
  var wire = @[0'u8, 0, byte(bytes.len)]
  for octet in bytes: wire.add(octet)
  var mask = newSeq[byte]((bytes.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for octet in mask: wire.add(octet)
  let captured = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(128), JumpCountLimit(0))
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
  for index in 0..<21: parts.add(@[149'u8, 17, 1]) # Twenty-one additions plus decrement/branch exceed the fixed decoder memo capacity.
  parts.add(@[149'u8, 0, 255])
  parts.add(@[82'u8, 16, 0, 190]) # Literal minus66 targets the original block start after all twenty-two mutations.
  parts.add(@[0'u8])
  let crowded = input(code(parts), 3)
  let completed = execute(crowded, ExecutionStepLimit(70), GasCycleLimit(10000))
  assert completed.error == StepError.None and completed.value.exit == StepExit.Panic
  same(machineInfo(completed.value.machine).value, compareSteps(crowded, 70))
  assert uint64(machineInfo(completed.value.machine).value.registers[0]) == 0
  assert uint64(machineInfo(completed.value.machine).value.registers[1]) == 63
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

collisions()
threeWayPressure()
alternatingPrices()
pricePressure()
hosts()
finalFallthrough()
let before = getOccupiedMem()
for cycle in 0..<1000:
  collisions()
  threeWayPressure()
  alternatingPrices()
  pricePressure()
  finalFallthrough()
  hosts() # Both bounded memos and all observable/nested snapshot owners retire after each complete invocation group.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_execution_cache", 1000, before, after)
echo "PVM invocation decoder cache passed"
echo "ARC_RELEASE cycles=1000 unchanged"
