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
for action in [HostAction.Panic, HostAction.OutOfGas]:
  var context = Context(calls: 0, action: action, badMemory: false)
  let stopped = executeWithHost(source(2), context, terminalSecond, ExecutionStepLimit(2),
    HostCallLimit(2), GasCycleLimit(0))
  let expected = (if action == HostAction.Panic: StepExit.Panic else: StepExit.OutOfGas)
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

type
  MeteredContext = object ## Counts loop callbacks without retaining any guest state or program owner.
    calls: uint64
  MeteredRefusal = enum ## A distinct local refusal domain selects the fallible callback API.
    Refused

proc meteredRespond(context: var MeteredContext, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## Preserve gas and code while mutating ordinary register state on each fixed-program continuation.
  let cpu = machineInfo(stopped.machine).value
  assert stopped.exit == StepExit.Host and uint64(stopped.hostCall) == 7
  assert uint64(cpu.pc) == 0 and uint64(cpu.registers[10]) == context.calls
  if context.calls == 0:
    # A callback may reenter another program at the same PC; its memo and gas remain independent.
    let nestedSource = source(0)
    let nestedProgram = programOf(nestedSource).value
    let nestedPrice = uint64(blockGas(nestedProgram, CodeAddress(0), GasCycleLimit(1000)).value)
    var nestedCpu = machineInfo(nestedSource).value
    nestedCpu.blockCharged = false
    nestedCpu.gas = MachineGas(nestedPrice + 7)
    let nested = captureMachine(nestedProgram, memoryOf(nestedSource).value, nestedCpu).value
    let finished = execute(nested, ExecutionStepLimit(1), GasCycleLimit(nestedPrice + 3)).value
    assert finished.exit == StepExit.Halt and uint64(machineInfo(finished.machine).value.gas) == 7
    assert uint64(machineInfo(nested).value.gas) == nestedPrice + 7
  inc context.calls
  var registers = cpu.registers
  registers[8] = RegisterValue(context.calls)
  HostResponse(action: HostAction.Continue, gas: cpu.gas, registers: registers,
    memory: memoryOf(stopped.machine).value)

proc meteredFallible(context: var MeteredContext, stopped: StepOutcome): HostResult[
    MeteredRefusal] {.raises: [].} =
  ## Exercise the typed callback form with the identical successful response semantics.
  hostSuccess[MeteredRefusal](meteredRespond(context, stopped))

# Seventeen visits pay the same block price across actual host replies; no call inherits another's memo.
block meteredInvocationIsolation:
  let wire = @[0'u8, 0, 17, 10, 7, 131, 0xaa, 1, 83, 0x4a, 17, 0, 0, 0, 251, 255,
    255, 255, 50, 0, 37, 128, 0]
  let code = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(128), JumpCountLimit(0)).value
  let price = uint64(blockGas(code, CodeAddress(0), GasCycleLimit(1000)).value)
  let haltPrice = uint64(blockGas(code, CodeAddress(15), GasCycleLimit(1000)).value)
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(0xffff0000'u64)
  let initial = captureMachine(code, captureMemory([], PageLimit(0)).value,
    MachineInfo(pc: CodeAddress(0), gas: MachineGas(price * 17 + haltPrice + 7),
      blockCharged: false, registers: registers)).value
  var plainContext = MeteredContext(calls: 0)
  var typedContext = MeteredContext(calls: 0)
  let plain = executeWithHost(initial, plainContext, meteredRespond, ExecutionStepLimit(52),
    HostCallLimit(17), GasCycleLimit(price + 3))
  let typed = executeWithHost(initial, typedContext, meteredFallible, ExecutionStepLimit(52),
    HostCallLimit(17), GasCycleLimit(price + 3))
  assert plain.error == StepError.None and typed.error == HostExecutionError.None
  let completed = [plain.value, typed.value]
  for result in completed:
    # Both embeddings preserve exact debits and all unrelated initial registers.
    let cpu = machineInfo(result.machine).value
    assert result.exit == StepExit.Halt and uint64(cpu.pc) == 0 and uint64(cpu.gas) == 7
    for i in 0..<13:
      let expected = if i in [8, 10]: 17'u64 else: uint64(registers[i])
      assert uint64(cpu.registers[i]) == expected
  assert plainContext.calls == 17 and typedContext.calls == 17
  plainContext.calls = 0
  typedContext.calls = 0
  # A previous successful higher-limit invocation cannot bypass fresh simulation under a lower limit.
  assert executeWithHost(initial, plainContext, meteredRespond, ExecutionStepLimit(52),
    HostCallLimit(17), GasCycleLimit(price + 2)).error == StepError.GasCycleLimitExceeded
  let lower = executeWithHost(initial, typedContext, meteredFallible, ExecutionStepLimit(52),
    HostCallLimit(17), GasCycleLimit(price + 2))
  assert lower.error == HostExecutionError.ExecutionFailure and lower.executionError ==
      StepError.GasCycleLimitExceeded
  assert plainContext.calls == 0 and typedContext.calls == 0
  # Dispatch and instruction refusal retain prior observable callback effects in both forms.
  assert executeWithHost(initial, plainContext, meteredRespond, ExecutionStepLimit(52),
    HostCallLimit(16), GasCycleLimit(price + 3)).error == StepError.HostCallLimitExceeded
  let short = executeWithHost(initial, typedContext, meteredFallible, ExecutionStepLimit(51),
    HostCallLimit(17), GasCycleLimit(price + 3))
  assert short.error == HostExecutionError.ExecutionFailure and short.executionError ==
      StepError.StepLimitExceeded
  assert plainContext.calls == 16 and typedContext.calls == 17
  let unchanged = machineInfo(initial).value
  assert uint64(unchanged.gas) == price * 17 + haltPrice + 7 and not unchanged.blockCharged
  for i in 0..<13:
    # No successful or refused invocation mutates the caller's retained source snapshot.
    assert uint64(unchanged.registers[i]) == uint64(registers[i])

type
  RetainedReason {.pure.} = enum ## Explicit local refusal never carries a partially resumed machine.
    Refused
  RetainedContext = object ## The callback intentionally keeps all published roots across subsequent resumption and refusal.
    calls: int
    refuse: bool
    roots: seq[Machine]

proc retainedReply(context: var RetainedContext, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## Observe the previous response, retain its genuine snapshot, then return independently owned posterior bytes/registers.
  let cpu = machineInfo(stopped.machine).value
  let memory = memoryOf(stopped.machine).value
  assert stopped.exit == StepExit.Host and uint64(stopped.hostCall) == 7
  assert uint64(cpu.pc) == uint64(context.calls*2) and cpu.blockCharged
  assert uint64(cpu.registers[8]) == uint64(context.calls)
  assert uint64(cpu.gas) == uint64(100000-context.calls)
  assert uint64(load(memory, MemoryAddress(65536), AccessWidth(8)).value) == uint64(context.calls)
  context.roots.add(stopped.machine)
  inc context.calls
  var registers = cpu.registers
  registers[8] = RegisterValue(uint64(context.calls))
  let updated = store(memory, MemoryAddress(65536), AccessWidth(8), RegisterValue(uint64(
      context.calls))).value
  HostResponse(action: HostAction.Continue, gas: MachineGas(uint64(100000-context.calls)),
    gasDeficit: GasDeficit(0), registers: registers, memory: updated)

proc retainedFallible(context: var RetainedContext, stopped: StepOutcome): HostResult[
    RetainedReason] {.raises: [].} =
  ## Completed callback observations persist when a later typed refusal prevents posterior state application.
  let reply = retainedReply(context, stopped)
  if context.refuse and context.calls == 3:
    return hostFailure[RetainedReason](RetainedReason.Refused)
  hostSuccess[RetainedReason](reply)

proc retainedCycle() =
  ## Compare full CPU/page observations for both APIs, including a callback refusal and post-reply instruction exhaustion.
  let memory = captureMemory([PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte]))], PageLimit(1)).value
  let initial = withMemory(source(4), memory).value
  for mode in 0..<3:
    var context = RetainedContext(calls: 0, refuse: mode == 1, roots: @[])
    if mode == 0:
      let run = executeWithHost(initial, context, retainedReply, ExecutionStepLimit(5),
          HostCallLimit(4), GasCycleLimit(0))
      assert run.error == StepError.None and run.value.exit == StepExit.Halt
      assert uint64(machineInfo(run.value.machine).value.gas) == 99996
      assert uint64(load(memoryOf(run.value.machine).value, MemoryAddress(65536), AccessWidth(
          8)).value) == 4
    elif mode == 1:
      let run = executeWithHost(initial, context, retainedFallible, ExecutionStepLimit(5),
          HostCallLimit(4), GasCycleLimit(0))
      assert run.error == HostExecutionError.HostFailure and run.hostError == RetainedReason.Refused
    else:
      let run = executeWithHost(initial, context, retainedFallible, ExecutionStepLimit(4),
          HostCallLimit(4), GasCycleLimit(0))
      assert run.error == HostExecutionError.ExecutionFailure and run.executionError ==
          StepError.StepLimitExceeded
    assert context.calls == (if mode == 1: 3 else: 4) and context.roots.len == context.calls
    for index in 0..<context.roots.len:
      # All retained CPU fields and every byte must still describe the instant before that callback's reply.
      let cpu = machineInfo(context.roots[index]).value
      assert uint64(cpu.pc) == uint64(index*2) and uint64(cpu.gas) == uint64(100000-index)
      assert uint64(cpu.gasDeficit) == 0 and cpu.blockCharged
      for register in 0..<13:
        let expected = if register == 0: 0xffff0000'u64 elif register == 8: uint64(
            index) else: 0'u64
        assert uint64(cpu.registers[register]) == expected
      let image = pageImage(memoryOf(context.roots[index]).value, PageIndex(16)).value
      assert image.access == PageAccess.ReadWrite
      for offset in 0..<4096:
        assert image.bytes[offset] == (if offset == 0: byte(index) else: 0'u8)
    assert uint64(machineInfo(initial).value.registers[8]) == 0
    assert uint64(load(memoryOf(initial).value, MemoryAddress(65536), AccessWidth(8)).value) == 0

# All roots and context values die at each invocation boundary, including failure after callback effects.
proc cycle() =
  var context = Context(calls: 0, action: HostAction.Continue, badMemory: false)
  assert executeWithHost(source(4), context, respond, ExecutionStepLimit(5), HostCallLimit(4),
    GasCycleLimit(0)).value.exit == StepExit.Halt
  context.calls = 0
  assert executeWithHost(source(4), context, respond, ExecutionStepLimit(2), HostCallLimit(4),
    GasCycleLimit(0)).error == StepError.StepLimitExceeded

cycle()
retainedCycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Repeated synchronous dispatch retains neither machine history nor callback/context references.
  cycle()
  retainedCycle() # Retained callback roots never alias the private continuation CPU or writable successors.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_host_execution", 1000, before, after)
echo "PVM host execution passed"
echo "ARC_RELEASE cycles=1000 unchanged"
