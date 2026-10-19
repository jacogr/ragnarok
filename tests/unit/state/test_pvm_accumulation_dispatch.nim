# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored accumulation dispatch witnesses exercise identifier classification and real engine execution.
## Tests preserve local refusals, exact gas outcomes, preparation ownership and ARC release.

## Verification: {"arc": "pvm_accumulation_dispatch_arc_release"}

import std/[assertions, syncio]
import ../../../src/state/[accumulation_machine, accumulation_dispatch]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, c2_records]
import ../../../src/pvm/[initialize, program, machine, host_fetch, step, gas]
import ../../support/[pvm_accumulation_context, arc_evidence]

## Prepare an actual bound service with ecalli at PC 5 and a dynamic return at PC 7.
proc prepared(id: byte, credit = 10000'u64): PreparedAccumulationMachine =
  initializeAccumulationMachine(pvmBootstrap(pvmEnvelope(
    [0'u8, 0, 9, 0, 0, 0, 0, 0, 10, id, 50, 0, 191, 0]), credit),
    InitializationLimits(envelope: InitializationByteLimit(64), program: ProgramByteLimit(32),
      jumps: JumpCountLimit(0), pages: PageLimit(5))).value

## A present empty input list still needs its canonical one-byte count.
proc limits(): FetchAccumulationLimits =
  FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
    operand: OperandLimits(maxBytes: ByteLimit(132)))

## Use independently configurable engine budgets; zero copy policy permits zero-length fetch queries.
proc run(source: PreparedAccumulationMachine, steps = 2'u64, calls = 1'u64,
    cycles = 200'u64): AccumulationDispatchResult =
  executeAccumulationMachine(source, pvmParameters(), limits(), MemoryByteLimit(0),
    ExecutionStepLimit(steps), HostCallLimit(calls), GasCycleLimit(cycles))

for id in [1'u8, 3, 4, 5, 6, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27]:
  # Every known unavailable accumulation call refuses locally instead of charging WHAT.
  assert run(prepared(id)).error == AccumulationDispatchError.UnsupportedHostCall
for id in [7'u8, 8, 9, 10, 11, 12, 13, 14, 28, 127, 255]:
  # Refine-only identifiers and the sign-extended full-width identifier all use F's fallback.
  let done = run(prepared(id))
  assert done.error == AccumulationDispatchError.None
  assert done.value.exit == StepExit.Halt
  assert uint64(machineInfo(done.value.machine).value.registers[7]) == high(uint64)-1
for id in [0'u8, 2, 28, 255]:
  let cost = (if id == 0: 48'u64 elif id == 2: 390'u64 else: 1000'u64)
  let source = prepared(id)
  let initial = source.accumulationMachine.value
  let price = uint64(blockGas(programOf(initial).value, CodeAddress(5), GasCycleLimit(200)).value)
  for available in [0'u64, cost-1, cost, cost+1]:
    # The independent block cost establishes exact host credit, without bypassing initialization.
    let done = run(prepared(id, price+available))
    assert done.error == AccumulationDispatchError.None
    let cpu = machineInfo(done.value.machine).value
    if available < cost:
      # Terminal deficits retain causing PC and preserve r7 except for F's mandatory WHAT assignment.
      assert done.value.exit == StepExit.OutOfGas
      assert uint64(cpu.gas) == 0 and uint64(cpu.gasDeficit) == cost-available
      assert uint64(cpu.pc) == 5
      let expected = (if id == 28 or id == 255: high(uint64)-1 else: 0xfeff0000'u64)
      assert uint64(cpu.registers[7]) == expected
    else:
      # Funded calls execute the prepaid return; zero requested bytes still returns parameter length.
      assert done.value.exit == StepExit.Halt
      assert uint64(cpu.gas) == available-cost and uint64(cpu.gasDeficit) == 0
      let expected = (if id == 0: available-cost elif id == 2: 122'u64 else: high(uint64)-1)
      assert uint64(cpu.registers[7]) == expected
  assert uint64(machineInfo(initial).value.gas) == 10000 # All successors leave the input intact.
let source = prepared(2)
for policy in 0..<3:
  # The adapter retains the engine's exact refusal instead of publishing partial progress.
  let done = (if policy == 0: run(source, steps = 0)
    elif policy == 1: run(source, calls = 0) else: run(source, cycles = 0))
  let expected = (if policy == 0: StepError.StepLimitExceeded
    elif policy == 1: StepError.HostCallLimitExceeded else: StepError.GasCycleLimitExceeded)
  assert done.error == AccumulationDispatchError.ExecutionFailure
  assert done.executionError == expected
assert run(default(PreparedAccumulationMachine)).error == AccumulationDispatchError.InvalidMachine
assert executeAccumulationMachine(source, default(Parameters), limits(), MemoryByteLimit(0),
  ExecutionStepLimit(2), HostCallLimit(1), GasCycleLimit(200)).error ==
  AccumulationDispatchError.InvalidParameters
assert executeAccumulationMachine(source, pvmParameters(), default(FetchAccumulationLimits),
  MemoryByteLimit(0), ExecutionStepLimit(2), HostCallLimit(1), GasCycleLimit(200)).error ==
  AccumulationDispatchError.LimitExceeded
# Request one parameter byte at the initialized read-only argument address.
let copying = initializeAccumulationMachine(pvmBootstrap(pvmEnvelope(
  [0'u8, 0, 12, 0, 0, 0, 0, 0, 51, 9, 1, 10, 2, 50, 0, 63, 5]), 10000),
  InitializationLimits(envelope: InitializationByteLimit(64), program: ProgramByteLimit(32),
    jumps: JumpCountLimit(0), pages: PageLimit(5))).value
assert run(copying, steps = 3).error == AccumulationDispatchError.LimitExceeded
let panicked = executeAccumulationMachine(copying, pvmParameters(), limits(), MemoryByteLimit(1),
  ExecutionStepLimit(3), HostCallLimit(1), GasCycleLimit(200))
assert panicked.error == AccumulationDispatchError.None and panicked.value.exit == StepExit.Panic
# Sufficient block gas still leaves an unavailable known call as a local scope refusal.
let known = prepared(1)
let knownPrice = uint64(blockGas(programOf(known.accumulationMachine.value).value,
  CodeAddress(5), GasCycleLimit(200)).value)
assert run(prepared(1, knownPrice)).error == AccumulationDispatchError.UnsupportedHostCall
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Repeated execution captures/releases its own environment and never advances the original CPU.
  let done = run(source)
  assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt
  assert uint64(machineInfo(done.value.machine).value.registers[7]) == 122
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_accumulation_dispatch", 1000, before, after)
echo "PVM accumulation dispatch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
