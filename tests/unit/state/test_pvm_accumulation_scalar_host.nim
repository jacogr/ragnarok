# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual accumulation dispatch mixes scalar gas/checkpoint with owned unknown/yield observations.
## Literal bytes, effect commitments and host charges remain independent of callback representation.

import std/[assertions, syncio]
import ../../../src/state/accumulation/[machine as accumulation_machine,
  dispatch as accumulation_dispatch, context as accumulation_context,
  effects as accumulation_effects]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, c2_records]
import ../../../src/pvm/[program, machine, step, worker]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/host/fetch
import ../../support/[pvm_accumulation_context, pvm_accumulation_program]

proc storeFirst(value: byte): seq[byte] =
  ## A literal absolute byte store targets the initializer's genuine writable page at 0x30000.
  assert value < 128
  @[30'u8, 3, 0, 0, 3, value]

proc limits(): FetchAccumulationLimits =
  ## Preserve the actual captured empty operand list and the existing full context bounds.
  FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
    operand: OperandLimits(maxBytes: ByteLimit(132)))

proc run(prepared: PreparedAccumulationMachine, execution: ExecutionWorker,
    steps = 14'u64, calls = 8'u64): AccumulationDispatchResult =
  ## This is the real worker/dispatcher entry point; no test-only callback or effect executor is substituted.
  executeAccumulationMachine(prepared, pvmParameters(), limits(), MemoryByteLimit(32),
    ExecutionStepLimit(steps), HostCallLimit(calls), GasCycleLimit(10000), pvmContextConfig(),
    backend = PvmBackend.Interpreted, worker = execution)

proc checkYield(done: AccumulationDispatchResult, dimension: AccumulationDimension,
    first: byte) =
  ## A retained effect commitment describes its yield instant, even after subsequent guest writes.
  let context = done.effects.effectContext(dimension).value
  assert context.effectInfo.value.hasYield
  let bytes = array[32, byte](context.effectYield.value)
  assert bytes[0] == first
  for at in 1..<32: assert bytes[at] == 0

block actualMixedDispatch:
  let instructions = [storeFirst(41), @[10'u8, 0], @[10'u8, 30], @[10'u8, 19],
    registerImmediate(7, 196608), @[10'u8, 27], storeFirst(73), @[10'u8, 0],
    registerImmediate(7, 196608), @[10'u8, 27], @[10'u8, 19], storeFirst(99),
    @[10'u8, 0], @[50'u8, 0]]
  let execution = newExecutionWorker()
  let prepared = guestProgram(instructions, worker = execution)
  let original = prepared.accumulationMachine.value
  let owner = programOf(original).value
  let price = uint64(blockGas(owner, CodeAddress(5), GasCycleLimit(10000)).value)
  for invocation in 0..<2:
    # Exact reused source/cache input must restore both prior scalar and owned writes completely.
    let done = run(prepared, execution)
    assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt
    let cpu = machineInfo(done.value.machine).value
    # Three gas, one owned unknown, two checkpoint and two yield callbacks charge 144+1000+206+196.
    assert uint64(cpu.gas) == 10000-price-1546
    assert uint64(cpu.registers[7]) == uint64(cpu.gas)
    # The last guest store crosses a scalar reply before final publication; no owned callback can mask it.
    assert uint64(load(memoryOf(done.value.machine).value, MemoryAddress(196608),
      AccessWidth(1)).value) == 99
    checkYield(done, AccumulationDimension.Regular, 73)
    checkYield(done, AccumulationDimension.Exceptional, 73)
    assert uint64(load(memoryOf(original).value, MemoryAddress(196608), AccessWidth(1)).value) == 81
  let shortHost = run(prepared, execution, calls = 7)
  assert shortHost.error == AccumulationDispatchError.ExecutionFailure
  assert shortHost.executionError == StepError.HostCallLimitExceeded
  let shortSteps = run(prepared, execution, steps = 13)
  assert shortSteps.error == AccumulationDispatchError.ExecutionFailure
  assert shortSteps.executionError == StepError.StepLimitExceeded
  assert uint64(load(memoryOf(original).value, MemoryAddress(196608), AccessWidth(1)).value) == 81

block scalarCheckpointTerminal:
  let instructions = [storeFirst(41), @[10'u8, 19], @[50'u8, 0]]
  let execution = newExecutionWorker()
  let prototype = guestProgram(instructions).accumulationMachine.value
  let price = uint64(blockGas(programOf(prototype).value, CodeAddress(5),
    GasCycleLimit(10000)).value)
  let prepared = guestProgram(instructions, credit = price+102, worker = execution)
  let done = run(prepared, execution, steps = 2, calls = 1)
  assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.OutOfGas
  let cpu = machineInfo(done.value.machine).value
  assert uint64(cpu.pc) == 11 and uint64(cpu.gas) == 0 and uint64(cpu.gasDeficit) == 0
  assert uint64(cpu.registers[7]) ==
    uint64(machineInfo(prepared.accumulationMachine.value).value.registers[7])
  assert uint64(load(memoryOf(done.value.machine).value, MemoryAddress(196608),
    AccessWidth(1)).value) == 41
  for dimension in [AccumulationDimension.Regular, AccumulationDimension.Exceptional]:
    # Underfunding precedes checkpoint assignment; unpublished guest bytes still belong to the final result.
    assert not done.effects.effectContext(dimension).value.effectInfo.value.hasYield

echo "PVM accumulation scalar and owned host checks passed"
