# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded host-aware execution witnesses: shared budgets, context ordering and terminal state.
## Exercises trusted callback failures, immutable snapshots and complete ARC lifetimes.

# @@Verification={"arc": "pvm_host_execution_arc_release"}

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, gas, step]
import ../../support/arc_evidence

# Plain value context records synchronous callback order without hidden global state or pointers.
type Context = object
  calls: int
  action: HostAction
  badMemory: bool

# Generate independently framed ecalli 7 instructions followed by the r0 dynamic halt sentinel.
proc source(count: int): Machine =
  var raw = @[0'u8, 0, byte(count * 2 + 2)]
  for i in 0..<count:
    # Every call has one immediate byte, so expected PCs are independently known even offsets.
    raw.add(10)
    raw.add(7)
  raw.add(50)
  raw.add(0)
  var mask = newSeq[byte]((count * 2 + 9) div 8)
  for i in 0..count:
    # Only even positions begin instructions.
    mask[(i * 2) div 8] = mask[(i * 2) div 8] or (1'u8 shl ((i * 2) mod 8))
  for value in mask:
    # Mask bytes follow the complete instruction payload.
    raw.add(value)
  let code = decodeProgram(raw, CodeAddress(0), ProgramByteLimit(256), JumpCountLimit(0)).value
  var cpu = MachineInfo(pc: CodeAddress(0), gas: MachineGas(100000), blockCharged: true,
    registers: default(RegisterFile))
  cpu.registers[0] = RegisterValue(0xffff0000'u64)
  captureMachine(code, captureMemory([], PageLimit(0)).value, cpu).value

# Preserve memory and all other registers while recording each delivered host call in context and r8.
proc respond(context: var Context, suspension: StepOutcome): HostResponse {.raises: [].} =
  assert suspension.exit == StepExit.Host and uint64(suspension.hostCall) == 7
  let cpu = machineInfo(suspension.machine).value
  assert uint64(cpu.pc) == uint64(context.calls * 2)
  assert uint64(cpu.registers[8]) == uint64(context.calls)
  inc context.calls
  var registers = cpu.registers
  registers[8] = RegisterValue(uint64(context.calls))
  let memory = (if context.badMemory: default(Memory) else: memoryOf(suspension.machine).value)
  HostResponse(action: context.action, gas: MachineGas(0), registers: registers, memory: memory)

# Defer a configured terminal response until the second call to witness a nonzero causing PC.
proc terminalSecond(context: var Context, suspension: StepOutcome): HostResponse {.raises: [].} =
  result = respond(context, suspension)
  if context.calls == 1:
    # The first response continues; the second retains its independently selected terminal action.
    result.action = HostAction.Continue

# Exact budgets across many host segments prove that instruction limits are never reset after a call.
for count in [0, 1, 2, 40]:
  var context = Context(calls: 0, action: HostAction.Continue, badMemory: false)
  let original = source(count)
  let done = executeWithHost(original, context, respond, ExecutionStepLimit(uint64(count + 1)),
    HostCallLimit(uint64(count)), GasCycleLimit(0))
  assert done.error == StepError.None and done.value.exit == StepExit.Halt
  assert context.calls == count
  assert uint64(machineInfo(done.value.machine).value.registers[8]) == uint64(count)
  assert uint64(machineInfo(original).value.registers[8]) == 0
  context.calls = 0
  let short = executeWithHost(original, context, respond, ExecutionStepLimit(uint64(count)),
    HostCallLimit(uint64(count)), GasCycleLimit(0))
  assert short.error == StepError.StepLimitExceeded
  assert context.calls == count

# A dispatch limit refuses before the next callback, while completed context mutations remain visible.
for permitted in [0, 1, 2]:
  var context = Context(calls: 0, action: HostAction.Continue, badMemory: false)
  let stopped = executeWithHost(source(3), context, respond, ExecutionStepLimit(4),
    HostCallLimit(uint64(permitted)), GasCycleLimit(0))
  assert stopped.error == StepError.HostCallLimitExceeded
  assert context.calls == permitted

# A terminal host response completes even when its ecalli used the last available guest attempt.
for action in [HostAction.Halt, HostAction.Panic, HostAction.OutOfGas]:
  var context = Context(calls: 0, action: action, badMemory: false)
  let stopped = executeWithHost(source(2), context, terminalSecond, ExecutionStepLimit(2),
    HostCallLimit(2), GasCycleLimit(0))
  let expected = (if action == HostAction.Halt: StepExit.Halt
    elif action == HostAction.Panic: StepExit.Panic else: StepExit.OutOfGas)
  assert stopped.error == StepError.None and stopped.value.exit == expected
  let cpu = machineInfo(stopped.value.machine).value
  assert uint64(cpu.pc) == 2 and uint64(cpu.gas) == 0 and cpu.blockCharged
  assert uint64(cpu.registers[8]) == 2 and context.calls == 2

# Failed replies do not roll back caller context, but expose no successful machine result.
for badMemory in [false, true]:
  var context = Context(calls: 0, action: (if badMemory: HostAction.Continue
    else: HostAction.Uninitialized), badMemory: badMemory)
  assert executeWithHost(source(1), context, respond, ExecutionStepLimit(2),
    HostCallLimit(1), GasCycleLimit(0)).error == StepError.InvalidHostResponse
  assert context.calls == 1

# Absent machine owners fail without invoking any callback.
var context = Context(calls: 0, action: HostAction.Continue, badMemory: false)
assert executeWithHost(default(Machine), context, respond, ExecutionStepLimit(1), HostCallLimit(1),
  GasCycleLimit(0)).error == StepError.InvalidMachine
assert context.calls == 0
# Uncharged zero gas stops in the guest before any host callback.
var cpu = machineInfo(source(1)).value
cpu.gas = MachineGas(0)
cpu.blockCharged = false
let starved = captureMachine(programOf(source(1)).value, memoryOf(source(1)).value, cpu).value
assert executeWithHost(starved, context, respond, ExecutionStepLimit(2), HostCallLimit(1),
  GasCycleLimit(1000)).value.exit == StepExit.OutOfGas
assert context.calls == 0

# Guest panic and page fault pass through unchanged, with no host callback or context mutation.
for fault in [false, true]:
  let bytes = (if fault: @[0'u8, 0, 6, 52, 0, 0, 0, 1, 0, 33]
    else: @[0'u8, 0, 1, 0, 1])
  let code = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(16), JumpCountLimit(0)).value
  let original = captureMachine(code, memoryOf(source(0)).value, machineInfo(source(0)).value).value
  var untouched = Context(calls: 0, action: HostAction.Continue, badMemory: false)
  let plain = execute(original, ExecutionStepLimit(1), GasCycleLimit(0)).value
  let hosted = executeWithHost(original, untouched, respond, ExecutionStepLimit(1), HostCallLimit(0),
    GasCycleLimit(0)).value
  assert hosted.exit == plain.exit and untouched.calls == 0
  assert uint64(machineInfo(hosted.machine).value.gas) == uint64(machineInfo(
      plain.machine).value.gas)
  if fault:
    # Selected metadata remains available for guest memory recovery.
    assert uint32(hosted.faultPage) == uint32(plain.faultPage)

# All roots and context values die at each invocation boundary, including failure after callback effects.
proc cycle() =
  var context = Context(calls: 0, action: HostAction.Continue, badMemory: false)
  assert executeWithHost(source(4), context, respond, ExecutionStepLimit(5), HostCallLimit(4),
    GasCycleLimit(0)).value.exit == StepExit.Halt
  context.calls = 0
  assert executeWithHost(source(4), context, respond, ExecutionStepLimit(2), HostCallLimit(4),
    GasCycleLimit(0)).error == StepError.StepLimitExceeded

cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Repeated synchronous dispatch retains neither machine history nor callback/context references.
  cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_host_execution", 1000, before, after)
echo "PVM host execution passed"
echo "ARC_RELEASE cycles=1000 unchanged"
