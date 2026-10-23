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
proc compareSteps(source: Machine, attempts: int): MachineInfo =
  ## Public single-step execution never uses the invocation cache; its complete trace independently checks composition and exit normalization.
  assert attempts > 0
  result = default(MachineInfo) # Initialize the copied result even before the bounded positive trace is traversed.
  var current = source
  for index in 0..<attempts:
    let once = stepOnce(current, GasCycleLimit(10000))
    assert once.error == StepError.None
    if index+1 == attempts:
      assert once.value.exit == StepExit.Panic
      result = machineInfo(once.value.machine).value
      result.pc = CodeAddress(0) # Outer Psi normalizes the final trap while retaining all posterior CPU values.
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
collisions()
hosts()
let before = getOccupiedMem()
for cycle in 0..<1000:
  collisions()
  hosts() # Both bounded memos and all observable/nested snapshot owners retire after each complete invocation group.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_execution_cache", 1000, before, after)
echo "PVM invocation decoder cache passed"
echo "ARC_RELEASE cycles=1000 unchanged"
