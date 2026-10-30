# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real independently authenticated refinement and accumulation invocations reuse code while keeping CPU/RAM/output histories separate.

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, step, worker]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/host/fetch as host_fetch
import ../../../src/pvm/refinement_exports
import ../../../src/state/refinement/[bootstrap as refinement_bootstrap,
    outcome as refinement_outcome]
import ../../../src/state/accumulation/[machine as accumulation_machine,
    dispatch as accumulation_dispatch]
import ../../../src/codec/[bounded, composite]
import ../../support/[pvm_refinement_outcome, pvm_accumulation_context, pvm_accumulation_program]

proc refinementWitness(selected: PvmBackend) =
  ## Distinct complete state/package captures share only exact guest code; literal result bytes distinguish invocation RAM.
  let worker = newExecutionWorker()
  let instructions = @[@[51'u8, 3, 7], @[51'u8, 4, 8], @[51'u8, 5, 9], @[51'u8, 6, 10],
      @[10'u8, 0], refinementImmediate(7, 196608), refinementImmediate(8, 3), @[50'u8, 0]]
  let first = refinementFixture(instructions, worker = worker)
  let second = refinementFixture(instructions, writable = @[31'u8, 32, 33], worker = worker)
  assert programOf(first.bootstrapMachine.value).value == programOf(
      second.bootstrapMachine.value).value
  var policy = refinementLimits()
  policy.backend = selected
  let original = runRefinementInvocation(first, [], refinementInputs(), ExportOffset(0), policy, worker)
  assert original.error == RefinementInvocationError.None
  assert original.value.refinementOutput.value == @[21'u8, 22, 23]
  assert uint64(original.value.refinementInfo.value.gasUsed) == 149 # Independent GP block101 plus gas-host48.
  let cold = workerInfo(worker).value
  assert cold.preparations == 1 and cold.hits == 0
  let current = runRefinementInvocation(second, [], refinementInputs(), ExportOffset(0), policy, worker)
  assert current.error == RefinementInvocationError.None
  assert current.value.refinementOutput.value == @[31'u8, 32, 33]
  assert original.value.refinementOutput.value == @[21'u8, 22, 23]
  assert first.bootstrapMachine.value.memoryOf.value.pageImage(PageIndex(48)).value.bytes[0] == 21
  let warm = workerInfo(worker).value
  assert warm.preparations == 1 and warm.hits == 1
  assert warm.prepared.backend == selected
  if selected == PvmBackend.Interpreted:
    assert warm.prepared.nativeFragments == 0 and warm.prepared.nativeOperations == 0
  when defined(arm64) and (defined(linux) or defined(macosx)):
    if selected == PvmBackend.Jit:
      assert warm.prepared.nativeOperations > cold.prepared.nativeOperations
  policy.cycles = GasCycleLimit(999)
  let changedPolicy = runRefinementInvocation(second, [], refinementInputs(), ExportOffset(0),
      policy, worker)
  assert changedPolicy.error == RefinementInvocationError.None
  assert workerInfo(worker).value.preparations == 2
  assert uint64(workerInfo(worker).value.prepared.limits.cycles) == 999
  let changed = refinementFixture([refinementImmediate(7, 196608), refinementImmediate(8, 2),
      @[50'u8, 0]], worker = worker)
  assert programOf(changed.bootstrapMachine.value).value != programOf(
      first.bootstrapMachine.value).value
  let changedCode = runRefinementInvocation(changed, [], refinementInputs(), ExportOffset(0),
      policy, worker)
  assert changedCode.error == RefinementInvocationError.None
  assert changedCode.value.refinementOutput.value == @[21'u8, 22]
  assert workerInfo(worker).value.preparations == 3
  policy.steps = ExecutionStepLimit(0)
  let refused = runRefinementInvocation(second, [], refinementInputs(), ExportOffset(0), policy, worker)
  assert refused.error == RefinementInvocationError.ExecutionFailure
  assert refused.executionError == StepError.StepLimitExceeded
  assert original.value.refinementOutput.value == @[21'u8, 22, 23]

proc accumulationWitness(selected: PvmBackend) =
  ## Fresh entry-5 CPUs and distinct writable bytes pass the same production accumulator hosts with one retained worker.
  let worker = newExecutionWorker()
  let code = @[@[51'u8, 3, 7], @[51'u8, 4, 8], @[51'u8, 5, 9], @[51'u8, 6, 10],
      @[10'u8, 0], @[50'u8, 0]]
  let first = guestProgram(code, worker = worker)
  let second = guestProgram(code, writable = @[91'u8], worker = worker)
  assert programOf(first.accumulationMachine.value).value == programOf(
      second.accumulationMachine.value).value
  let fetch = FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
      operand: OperandLimits(maxBytes: ByteLimit(132)))
  let original = executeAccumulationMachine(first, pvmParameters(), fetch, MemoryByteLimit(0),
      ExecutionStepLimit(32), HostCallLimit(4), GasCycleLimit(1000), pvmContextConfig(),
      backend = selected, worker = worker)
  assert original.error == AccumulationDispatchError.None and original.value.exit == StepExit.Halt
  assert uint64(original.value.machine.machineInfo.value.pc) == 0
  assert original.value.machine.memoryOf.value.pageImage(PageIndex(48)).value.bytes[0] == 81
  let current = executeAccumulationMachine(second, pvmParameters(), fetch, MemoryByteLimit(0),
      ExecutionStepLimit(32), HostCallLimit(4), GasCycleLimit(1000), pvmContextConfig(),
      backend = selected, worker = worker)
  assert current.error == AccumulationDispatchError.None and current.value.exit == StepExit.Halt
  assert current.value.machine.memoryOf.value.pageImage(PageIndex(48)).value.bytes[0] == 91
  assert original.value.machine.memoryOf.value.pageImage(PageIndex(48)).value.bytes[0] == 81
  let warm = workerInfo(worker).value
  assert warm.preparations == 1 and warm.hits == 1
  assert warm.prepared.backend == selected
  if selected == PvmBackend.Interpreted:
    assert current.value.backend == PvmBackend.Interpreted
    assert warm.prepared.nativeOperations == 0
  when defined(arm64) and (defined(linux) or defined(macosx)):
    if selected == PvmBackend.Jit:
      assert current.value.backend == PvmBackend.Jit and warm.prepared.nativeOperations > 0
  assert current.value.machine.machineInfo.value.registers ==
      original.value.machine.machineInfo.value.registers
  # Independent pinned-table simulation prices this block101; Omega_G costs48, leaving9851.
  let actual = current.value.machine.machineInfo.value
  var expectedRegisters = second.accumulationMachine.value.machineInfo.value.registers
  expectedRegisters[3] = RegisterValue(7)
  expectedRegisters[4] = RegisterValue(8)
  expectedRegisters[5] = RegisterValue(9)
  expectedRegisters[6] = RegisterValue(10)
  expectedRegisters[7] = RegisterValue(9851)
  assert actual.registers == expectedRegisters
  assert uint64(actual.gas) == 9851 and uint64(actual.gasDeficit) == 0
  assert uint64(actual.pc) == 0 and actual.blockCharged

refinementWitness(PvmBackend.Interpreted)
refinementWitness(PvmBackend.Jit)
accumulationWitness(PvmBackend.Interpreted)
accumulationWitness(PvmBackend.Jit)
echo "PVM worker application passed"
