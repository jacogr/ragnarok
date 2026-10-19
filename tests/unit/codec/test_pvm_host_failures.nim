# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fallible host-loop witnesses preserve typed fetch refusals without exposing partial machine state.
## Covers shared budgets, malformed replies, context side effects, guest outcomes and ARC release.

# @@Verification={"arc": "pvm_host_failures_arc_release"}

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, gas, step, host_fetch]
import ../../support/arc_evidence

type
  # Test-only callback behavior distinguishes explicit refusals from malformed output and guest exits.
  Mode = enum
    Fetch, Refuse, Unselected, Malformed, Terminal
  # Plain caller-owned context records effects even when execution later refuses locally.
  Context = object
    calls: int
    selectedCall: int
    mode: Mode
    reason: FetchError
    limit: MemoryByteLimit
    action: HostAction

# Frame consecutive ecalli 2 instructions followed by a dynamic halt, with independently built masks.
proc source(count: int, available: uint64 = 10000, writable: bool = true): Machine =
  var raw = @[0'u8, 0, byte(count * 2 + 2)]
  for i in 0..<count:
    # Every host instruction has one byte of identifier and occupies two code bytes.
    raw.add(10)
    raw.add(2)
  raw.add(50)
  raw.add(0)
  var mask = newSeq[byte]((count * 2 + 9) div 8)
  for i in 0..count:
    # The final jump and every ecalli begin at independently known even offsets.
    mask[(i * 2) div 8] = mask[(i * 2) div 8] or (1'u8 shl ((i * 2) mod 8))
  for value in mask:
    # The framing bitmap follows the complete code sequence.
    raw.add(value)
  let code = decodeProgram(raw, CodeAddress(0), ProgramByteLimit(256), JumpCountLimit(0)).value
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(0xffff0000'u64)
  registers[9] = RegisterValue(1)
  registers[10] = RegisterValue(2)
  let page = PageImage(index: PageIndex(0),
    access: (if writable: PageAccess.ReadWrite else: PageAccess.ReadOnly))
  captureMachine(code, captureMemory([page], PageLimit(1)).value,
    MachineInfo(pc: CodeAddress(0), gas: MachineGas(available), blockCharged: true,
      registers: registers)).value

# Propagate fetch's exact enum; the adapter makes no guest exit out of a local refusal.
proc respond(context: var Context, stopped: StepOutcome): HostResult[FetchError] {.raises: [].} =
  assert stopped.exit == StepExit.Host and uint64(stopped.hostCall) == 2
  let cpu = machineInfo(stopped.machine).value
  assert uint64(cpu.pc) == uint64(context.calls * 2)
  inc context.calls
  if context.calls == context.selectedCall:
    # Configured failures occur after the observable context mutation, exposing rollback assumptions.
    case context.mode
    of Refuse:
      # No enum ordinal, including None and Uninitialized, is interpreted by the generic engine.
      return hostFailure(context.reason)
    of Unselected:
      # Default callback output is malformed rather than a host-selected failure.
      return default(HostResult[FetchError])
    of Malformed:
      # Explicit success still passes through applyHostResponse validation.
      return hostSuccess[FetchError](default(HostResponse))
    of Terminal:
      # Terminal guest outcomes remain completed results, with state inspectable by the caller.
      return hostSuccess[FetchError](HostResponse(action: context.action, gas: cpu.gas,
        registers: cpu.registers, memory: memoryOf(stopped.machine).value))
    of Fetch:
      # Normal dispatch below exercises the real bounded memory-copy operation.
      discard
  let fetched = fetchTraceResponse(cpu.gas, cpu.registers, memoryOf(stopped.machine).value,
    [17'u8, 19], context.limit)
  if fetched.error != FetchError.None:
    # A failed fetch exposes only its reason; no response accessor is attempted.
    return hostFailure(fetched.error)
  hostSuccess[FetchError](fetched.value)

# The established response-only API serves as an independent control on the shared scheduler.
proc respondRaw(context: var Context, stopped: StepOutcome): HostResponse {.raises: [].} =
  let reply = respond(context, stopped)
  assert reply.kind == HostResultKind.Response
  reply.value

# Exact and short budgets preserve behavior across both callback forms and many continuations.
for count in [0, 1, 2, 20]:
  var context = Context(limit: MemoryByteLimit(2))
  var control = Context(limit: MemoryByteLimit(2))
  let original = source(count)
  let done = executeWithHost(original, context, respond, ExecutionStepLimit(uint64(count + 1)),
    HostCallLimit(uint64(count)), GasCycleLimit(0))
  let plain = executeWithHost(original, control, respondRaw, ExecutionStepLimit(uint64(count + 1)),
    HostCallLimit(uint64(count)), GasCycleLimit(0))
  assert done.error == HostExecutionError.None and plain.error == StepError.None
  assert done.value.exit == StepExit.Halt and plain.value.exit == StepExit.Halt
  assert context.calls == count and control.calls == count
  assert uint64(machineInfo(done.value.machine).value.gas) == 10000 - uint64(count) * 81
  assert uint64(machineInfo(done.value.machine).value.gas) ==
    uint64(machineInfo(plain.value.machine).value.gas)
  assert pageImage(memoryOf(original).value, PageIndex(0)).value.bytes[0] == 0
  context.calls = 0
  let short = executeWithHost(original, context, respond, ExecutionStepLimit(uint64(count)),
    HostCallLimit(uint64(count)), GasCycleLimit(0))
  assert short.error == HostExecutionError.ExecutionFailure
  assert short.executionError == StepError.StepLimitExceeded and context.calls == count

for reason in [FetchError.Uninitialized, FetchError.None, FetchError.UnsupportedSelector,
    FetchError.InvalidMemory, FetchError.LimitExceeded]:
  # Every caller enum value is preserved verbatim, independently of its name or ordinal.
  for selected in [1, 2]:
    # Refusal after an earlier continuation must prevent all later dispatches and guest execution.
    var context = Context(selectedCall: selected, mode: Refuse, reason: reason,
        limit: MemoryByteLimit(2))
    let failed = executeWithHost(source(3), context, respond, ExecutionStepLimit(4),
      HostCallLimit(3), GasCycleLimit(0))
    assert failed.error == HostExecutionError.HostFailure and failed.hostError == reason
    assert context.calls == selected

# A refusal on the last permitted host instruction must win over a hypothetical next-step exhaustion.
var finalContext = Context(selectedCall: 2, mode: Refuse, reason: FetchError.LimitExceeded,
  limit: MemoryByteLimit(2))
let finalRefusal = executeWithHost(source(3), finalContext, respond, ExecutionStepLimit(2),
  HostCallLimit(2), GasCycleLimit(0))
assert finalRefusal.error == HostExecutionError.HostFailure
assert finalRefusal.hostError == FetchError.LimitExceeded and finalContext.calls == 2

for mode in [Unselected, Malformed]:
  # A missing result selection and an explicitly selected invalid response are engine errors.
  var context = Context(selectedCall: 2, mode: mode, limit: MemoryByteLimit(2))
  let failed = executeWithHost(source(3), context, respond, ExecutionStepLimit(4),
    HostCallLimit(3), GasCycleLimit(0))
  assert failed.error == HostExecutionError.ExecutionFailure
  assert failed.executionError == StepError.InvalidHostResponse and context.calls == 2

for permitted in [0, 1, 2]:
  # Dispatch exhaustion precedes callback effects; completed effects survive the local failure.
  var context = Context(limit: MemoryByteLimit(2))
  let failed = executeWithHost(source(3), context, respond, ExecutionStepLimit(4),
    HostCallLimit(uint64(permitted)), GasCycleLimit(0))
  assert failed.error == HostExecutionError.ExecutionFailure
  assert failed.executionError == StepError.HostCallLimitExceeded and context.calls == permitted

for action in [HostAction.Halt, HostAction.Panic, HostAction.OutOfGas]:
  # A host terminal response completes on the final instruction allowance at the nonzero causing PC.
  var context = Context(selectedCall: 2, mode: Terminal, action: action, limit: MemoryByteLimit(2))
  let done = executeWithHost(source(3), context, respond, ExecutionStepLimit(2),
    HostCallLimit(2), GasCycleLimit(0))
  assert done.error == HostExecutionError.None and context.calls == 2
  let expected = (if action == HostAction.Halt: StepExit.Halt
    elif action == HostAction.Panic: StepExit.Panic else: StepExit.OutOfGas)
  assert done.value.exit == expected and uint64(machineInfo(done.value.machine).value.pc) == 2

# Real fetch limit refusal is distinct from both a permission panic and guest gas underflow.
for writable in [false, true]:
  for credit in [0'u64, 81'u64]:
    # Copy policy is reached only after the host gas check; page access follows copy policy.
    var context = Context(limit: MemoryByteLimit(0))
    let done = executeWithHost(source(1, credit, writable), context, respond, ExecutionStepLimit(2),
      HostCallLimit(1), GasCycleLimit(0))
    assert context.calls == 1
    if credit == 0:
      # The host's negative gas balance remains a completed OutOfGas outcome, never a local failure.
      assert done.error == HostExecutionError.None and done.value.exit == StepExit.OutOfGas
      assert uint64(machineInfo(done.value.machine).value.gasDeficit) == 81
    else:
      # Neither writable nor readonly memory changes a local copy-limit refusal into a panic.
      assert done.error == HostExecutionError.HostFailure and done.hostError ==
          FetchError.LimitExceeded
var readonlyContext = Context(limit: MemoryByteLimit(1))
let panicked = executeWithHost(source(1, 81, false), readonlyContext, respond, ExecutionStepLimit(2),
  HostCallLimit(1), GasCycleLimit(0))
assert panicked.error == HostExecutionError.None and panicked.value.exit == StepExit.Panic
var invalidContext = Context(limit: MemoryByteLimit(1))
let invalid = executeWithHost(default(Machine), invalidContext, respond, ExecutionStepLimit(1),
  HostCallLimit(1), GasCycleLimit(0))
assert invalid.error == HostExecutionError.ExecutionFailure
assert invalid.executionError == StepError.InvalidMachine and invalidContext.calls == 0
let empty = default(HostExecutionResult[FetchError])
assert empty.error == HostExecutionError.Uninitialized
let unselected = default(HostResult[FetchError])
assert unselected.kind == HostResultKind.Uninitialized

# Guest outcomes are passed through without attempting host dispatch even with zero dispatch budget.
for fault in [false, true]:
  let raw = (if fault: @[0'u8, 0, 6, 52, 0, 0, 0, 1, 0, 33] else: @[0'u8, 0, 1, 0, 1])
  let code = decodeProgram(raw, CodeAddress(0), ProgramByteLimit(16), JumpCountLimit(0)).value
  let initial = source(0)
  let original = captureMachine(code, memoryOf(initial).value, machineInfo(initial).value).value
  var context = Context(limit: MemoryByteLimit(1))
  let plain = execute(original, ExecutionStepLimit(1), GasCycleLimit(0)).value
  let done = executeWithHost(original, context, respond, ExecutionStepLimit(1), HostCallLimit(0),
    GasCycleLimit(0))
  assert done.error == HostExecutionError.None and done.value.exit == plain.exit and
      context.calls == 0
  if fault:
    # Guest fault metadata remains selected and available for the caller's recovery policy.
    assert uint32(done.value.faultPage) == uint32(plain.faultPage)

# Release complete and locally failed invocations, including earlier successful memory writes.
proc cycle() =
  for limit in [0'u64, 2'u64]:
    # Both branches allocate source roots, while only the successful branch retains copied pages briefly.
    var context = Context(limit: MemoryByteLimit(limit))
    let done = executeWithHost(source(2), context, respond, ExecutionStepLimit(3), HostCallLimit(2),
      GasCycleLimit(0))
    assert done.error == (if limit == 0: HostExecutionError.HostFailure else: HostExecutionError.None)
  var context = Context(selectedCall: 2, mode: Refuse, reason: FetchError.LimitExceeded,
    limit: MemoryByteLimit(2))
  let failed = executeWithHost(source(3), context, respond, ExecutionStepLimit(4), HostCallLimit(3),
    GasCycleLimit(0))
  assert failed.error == HostExecutionError.HostFailure and context.calls == 2

cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # No result or engine frame retains the callback, context or earlier machine history.
  cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_host_failures", 1000, before, after)
echo "PVM host failures passed"
echo "ARC_RELEASE cycles=1000 unchanged"
