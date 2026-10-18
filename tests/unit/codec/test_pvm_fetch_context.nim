# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent optional fetch context witnesses for absence, charging, ownership and dispatch.
## Exercises immutable captures, unsupported selectors and fresh native ARC lifetimes.

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, gas, step, host_fetch]
import ../../support/arc_evidence

# A retained sentinel reveals any unintended memory mutation on absent-value replies.
proc memory(): Memory =
  var page = PageImage(index: PageIndex(0), access: PageAccess.ReadWrite)
  page.bytes[0] = 91
  captureMemory([page], PageLimit(1)).value

# Independent register sentinels expose mutation outside the specified r7 return value.
proc arguments(selector, pointer, offset, requested: uint64): RegisterFile =
  result = default(RegisterFile)
  for i in 0..<13:
    # Distinct input values make accidental whole-file clearing visible.
    result[i] = RegisterValue(uint64(i + 20))
  result[0] = RegisterValue(0xffff0000'u64)
  result[7] = RegisterValue(pointer)
  result[8] = RegisterValue(offset)
  result[9] = RegisterValue(requested)
  result[10] = RegisterValue(selector)

let emptyEntropy = FetchEntropy(default(array[32, byte]))
let absent = captureFetchContext(FetchPresence.Absent, emptyEntropy, FetchPresence.Absent, [],
  FetchTraceLimit(0)).value
let original = memory()
for selector in [1'u64, 2'u64, 16'u64, 17'u64, high(uint64)]:
  for requested in [0'u64, 1'u64, 1023'u64, 1024'u64, 1025'u64, high(uint64)]:
    # Small multiplication is an independent oracle; maximal trace cost is a hand-derived constant.
    let price = (if selector == 1: 103'u64 elif selector != 2: 80'u64
      elif requested == high(uint64): 1729382256910270544'u64
      else: 80 + (96 * requested + 1023) div 1024)
    for credit in [0'u64, price - 1, price, price + 1]:
      for pointer in [0'u64, 8192'u64, high(uint64)]:
        for offset in [0'u64, high(uint64)]:
          # |none| = 0 makes all destination/offset choices an empty copy, even with zero copy budget.
          let regs = arguments(selector, pointer, offset, requested)
          let response = fetchContextResponse(absent, MachineGas(credit), regs, original,
            MemoryByteLimit(0)).value
          assert pageImage(response.memory, PageIndex(0)).value.bytes[0] == 91
          if credit < price:
            # Underfunding precedes NONE assignment and retains the full exact deficit.
            assert response.action == HostAction.OutOfGas
            assert uint64(response.gas) == 0 and uint64(response.gasDeficit) == price - credit
          else:
            # A funded absent value continues with NONE regardless of requested length or pointer.
            assert response.action == HostAction.Continue
            assert uint64(response.gas) == credit - price and uint64(response.gasDeficit) == 0
          for i in 0..<13:
            # Only funded r7 changes; all other registers and underfunded r7 are preserved.
            assert uint64(response.registers[i]) == (if i == 7 and credit >= price: high(uint64)
              else: uint64(regs[i]))

for selector in [0'u64, 14'u64, 15'u64]:
  # Recognized selectors without implemented context must not fall into the unknown/NONE branch.
  assert fetchContextResponse(absent, MachineGas(10000), arguments(selector, 0, 0, 0),
    original, MemoryByteLimit(0)).error == FetchError.UnsupportedSelector

for entropyPresence in [FetchPresence.Absent, FetchPresence.Present]:
  for tracePresence in [FetchPresence.Absent, FetchPresence.Present]:
    # Every presence combination is independent, including present empty trace with absent entropy.
    let captured = captureFetchContext(entropyPresence, emptyEntropy, tracePresence, [],
        FetchTraceLimit(0)).value
    let entropyReply = fetchContextResponse(captured, MachineGas(103), arguments(1, high(uint64),
      32, 99), original, MemoryByteLimit(0)).value
    assert entropyReply.action == HostAction.Continue
    assert uint64(entropyReply.registers[7]) == (if entropyPresence ==
        FetchPresence.Present: 32'u64 else: high(uint64))
    let traceReply = fetchContextResponse(captured, MachineGas(80), arguments(2, high(uint64),
      high(uint64), 0), original, MemoryByteLimit(0)).value
    assert traceReply.action == HostAction.Continue
    assert uint64(traceReply.registers[7]) == (if tracePresence ==
        FetchPresence.Present: 0'u64 else: high(uint64))

# Capture selected bytes once; later mutation and destruction of caller storage cannot affect them.
proc capturedInputs(): FetchContext =
  var entropy = default(array[32, byte])
  entropy[0] = 73
  var trace = @[8'u8, 9, 10]
  let captured = captureFetchContext(FetchPresence.Present, FetchEntropy(entropy),
    FetchPresence.Present, trace, FetchTraceLimit(3)).value
  entropy[0] = 0
  trace[0] = 255
  trace.setLen(0)
  captured

let owned = capturedInputs()
let alias = owned
for selector in [1'u64, 2'u64]:
  # Copied context handles share private immutable storage; replies own independently written pages.
  let response = fetchContextResponse(alias, MachineGas(1000), arguments(selector, 0, 0, 1),
    original, MemoryByteLimit(1)).value
  assert response.action == HostAction.Continue
  assert uint64(response.registers[7]) == (if selector == 1: 32'u64 else: 3'u64)
  assert pageImage(response.memory, PageIndex(0)).value.bytes[0] == (if selector ==
      1: 73'u8 else: 8'u8)
  assert pageImage(original, PageIndex(0)).value.bytes[0] == 91
  let refused = fetchContextResponse(alias, MachineGas(1000), arguments(selector, 0, 0, 1),
    original, MemoryByteLimit(0))
  assert refused.error == FetchError.LimitExceeded
let clipped = fetchContextResponse(owned, MachineGas(1000), arguments(2, 4094, 1, 1), original,
  MemoryByteLimit(1)).value
assert uint64(clipped.registers[7]) == 3 and pageImage(clipped.memory, PageIndex(0)).value.bytes[4094] == 9
let panicked = fetchContextResponse(owned, MachineGas(1000), arguments(2, 4095, 0, 3), original,
  MemoryByteLimit(3)).value
assert panicked.action == HostAction.Panic
assert pageImage(panicked.memory, PageIndex(0)).value.bytes[4095] == 0
assert captureFetchContext(FetchPresence.Present, emptyEntropy, FetchPresence.Present,
  [1'u8, 2], FetchTraceLimit(1)).error == FetchError.LimitExceeded
# Ignored absent payloads neither consume the trace cap nor accidentally become selected values.
let ignored = captureFetchContext(FetchPresence.Absent, emptyEntropy, FetchPresence.Absent,
  [1'u8, 2], FetchTraceLimit(0)).value
assert uint64(fetchContextResponse(ignored, MachineGas(81), arguments(2, 0, 0, 1), original,
  MemoryByteLimit(0)).value.registers[7]) == high(uint64)
assert fetchContextResponse(default(FetchContext), MachineGas(1000), arguments(2, 0, 0, 0),
  original, MemoryByteLimit(0)).error == FetchError.InvalidContext
assert fetchContextResponse(absent, MachineGas(0), arguments(2, 0, 0, 0), default(Memory),
  MemoryByteLimit(0)).error == FetchError.InvalidMemory
let emptyResult = default(FetchContextResult)
assert emptyResult.error == FetchError.Uninitialized

# Application context retains an immutable fetch owner and a local copy cap; dispatch counts are external effects.
type Context = object
  fetch: FetchContext
  limit: MemoryByteLimit
  calls: int

# Dispatch host identifier 2 only, preserving typed local errors through the fallible host loop.
proc dispatch(context: var Context, stopped: StepOutcome): HostResult[FetchError] {.raises: [].} =
  assert uint64(stopped.hostCall) == 2
  inc context.calls
  let cpu = machineInfo(stopped.machine).value
  let response = fetchContextResponse(context.fetch, cpu.gas, cpu.registers,
    memoryOf(stopped.machine).value, context.limit)
  if response.error != FetchError.None:
    # No partial machine is made visible when local context or memory policy refuses a call.
    return hostFailure(response.error)
  hostSuccess[FetchError](response.value)

# Complete the captured context's lifecycle through host dispatch, or propagate its local copy refusal.
proc cycle() =
  let code = decodeProgram([0'u8, 0, 4, 10, 2, 50, 0, 5], CodeAddress(0), ProgramByteLimit(8),
    JumpCountLimit(0)).value
  for present in [false, true]:
    for limit in [0'u64, 1'u64]:
      # Each invocation owns fresh context and memory snapshots, released before the next ARC sample.
      var context = Context(fetch: (if present: capturedInputs() else:
        captureFetchContext(FetchPresence.Absent, emptyEntropy, FetchPresence.Absent, [],
            FetchTraceLimit(0)).value),
        limit: MemoryByteLimit(limit), calls: 0)
      let source = captureMachine(code, memory(), MachineInfo(pc: CodeAddress(0), gas: MachineGas(81),
        blockCharged: true, registers: arguments(2, 0, 0, 1))).value
      let done = executeWithHost(source, context, dispatch, ExecutionStepLimit(2), HostCallLimit(1),
          GasCycleLimit(0))
      assert context.calls == 1
      if present and limit == 0:
        # A present trace needs copy capacity; absence succeeds with the same zero-byte policy.
        assert done.error == HostExecutionError.HostFailure and done.hostError ==
            FetchError.LimitExceeded
      else:
        # NONE and full-length returns survive the guest halt without a second host dispatch.
        assert done.error == HostExecutionError.None and done.value.exit == StepExit.Halt
        let cpu = machineInfo(done.value.machine).value
        assert uint64(cpu.gas) == 0
        assert uint64(cpu.registers[7]) == (if present: 3'u64 else: high(uint64))

  # Default context failure must survive the host loop as the exact local reason.
  var invalid = Context(fetch: default(FetchContext), limit: MemoryByteLimit(0), calls: 0)
  let initial = captureMachine(code, memory(), MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000),
    blockCharged: true, registers: arguments(2, 0, 0, 0))).value
  let refused = executeWithHost(initial, invalid, dispatch, ExecutionStepLimit(2), HostCallLimit(1),
      GasCycleLimit(0))
  assert refused.error == HostExecutionError.HostFailure and refused.hostError ==
      FetchError.InvalidContext
  assert invalid.calls == 1

cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Captured owners have no back-references and callbacks retain no invocation history.
  cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_fetch_context", 1000, before, after)
echo "PVM fetch context passed"
echo "ARC_RELEASE cycles=1000 unchanged"
