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
import ../../../src/codec/[bounded, composite, c2_records]
import ../../support/[pvm_refinement_outcome, pvm_accumulation_context, pvm_accumulation_program]

when defined(pvmArm64Jit) and defined(arm64) and (defined(linux) or defined(macosx)):
  import ../../../src/state/refinement/report as refinement_report
  import ../../../src/codec/work/report as work_report
  import ../../support/pvm_report_results

  proc packageRuntimeWitness() =
    ## A package that can reuse its code submits once. A singleton with the same
    ## eligible program completes without a compiler submission.
    let guest = reportGuest([
      # Split setup at jumps so the first eligible pure span is the loop.
      refinementImmediate(7, 65536), @[40'u8, 2],
      @[51'u8, 8, 3], @[10'u8, 8], @[40'u8, 2],
      refinementImmediate(7, 178176), @[40'u8, 2],
      @[51'u8, 10, 0], @[40'u8, 2],
      refinementImmediate(11, 6144), @[40'u8, 2],
      # Each of 6,144 iterations adds three to R7 and one to R10.
      # R7 ends at the writable return address 196608.
      @[131'u8, 0x77, 3], @[131'u8, 0xaa, 1], @[172'u8, 0xba, 0xfa, 0xff, 0xff, 0xff],
      @[51'u8, 8, 3], @[50'u8, 0]], declared = 1, credit = 1000000)
    var limits = reportLimits()
    limits.invocation.backend = PvmBackend.Jit
    limits.invocation.steps = ExecutionStepLimit(20000)
    for count in [1, 2]:
      # Fresh runtimes make the submission count independent of compiler readiness.
      let fixture = if count == 1: reportFixture([guest]) else: reportFixture([guest, guest])
      let runtime = newNativeRuntime()
      try:
        assert runtime.start()
      except:
        assert false, "package compiler startup failed"
      let report = refinePackage(fixture.state, fixture.package, CoreIndex(5),
        fixture.parameters, [], fixture.inputs, limits, runtime)
      let submitted = runtime.runtimeInfo.submitted
      assert runtime.close()
      assert report.error == RefinementReportError.None
      assert report.value.reportInfo.value.items == count
      for index in 0..<count:
        # Check the literal result and gas before examining the native receipt.
        let item = report.value.reportItem(FetchItemIndex(uint64(index))).value
        assert item.refinedOutput.value == @[21'u8, 22, 23]
        assert uint64(item.refinedInfo.value.gasUsed) == 138872
      let expected = if count == 1: 0'u64 else: 1'u64
      assert submitted == expected, "package runtime submissions for " & $count & " items: " & $submitted

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
  # A worker without an explicit runtime never compiles synchronously to satisfy a native counter.
  assert warm.prepared.nativeOperations == 0
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
  # Requested Jit remains a checked-capable policy; this small unbound caller reports its actual engine.
  assert current.value.backend == PvmBackend.Interpreted and warm.prepared.nativeOperations == 0
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

proc checkedMemoryWitness(selected: PvmBackend) =
  ## The unported indirect-memory shape remains checked and must still use each invocation's own RAM.
  let worker = newExecutionWorker()
  let code = @[registerImmediate(11, 196608), @[124'u8, 185], @[51'u8, 3, 7],
      @[51'u8, 4, 8], @[51'u8, 5, 9], @[51'u8, 6, 10], @[10'u8, 0], @[50'u8, 0]]
  let first = guestProgram(code, writable = @[81'u8], worker = worker)
  let second = guestProgram(code, writable = @[91'u8], worker = worker)
  let fetch = FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
      operand: OperandLimits(maxBytes: ByteLimit(132)))
  let original = executeAccumulationMachine(first, pvmParameters(), fetch, MemoryByteLimit(0),
      ExecutionStepLimit(32), HostCallLimit(4), GasCycleLimit(1000), pvmContextConfig(),
      backend = selected, worker = worker)
  assert original.error == AccumulationDispatchError.None and original.value.exit == StepExit.Halt
  let current = executeAccumulationMachine(second, pvmParameters(), fetch, MemoryByteLimit(0),
      ExecutionStepLimit(32), HostCallLimit(4), GasCycleLimit(1000), pvmContextConfig(),
      backend = selected, worker = worker)
  assert current.error == AccumulationDispatchError.None and current.value.exit == StepExit.Halt
  assert uint64(original.value.machine.machineInfo.value.registers[9]) == 81
  let cpu = current.value.machine.machineInfo.value
  var expectedRegisters = second.accumulationMachine.value.machineInfo.value.registers
  expectedRegisters[3] = RegisterValue(7)
  expectedRegisters[4] = RegisterValue(8)
  expectedRegisters[5] = RegisterValue(9)
  expectedRegisters[6] = RegisterValue(10)
  expectedRegisters[7] = RegisterValue(9850)
  expectedRegisters[9] = RegisterValue(91)
  expectedRegisters[11] = RegisterValue(196608)
  assert cpu.registers == expectedRegisters
  assert uint64(cpu.gas) == 9850 and uint64(cpu.gasDeficit) == 0 # Independent GP102 plus host48.
  assert uint64(cpu.pc) == 0 and cpu.blockCharged
  assert original.value.machine.memoryOf.value.pageImage(PageIndex(48)).value.bytes[0] == 81
  assert current.value.machine.memoryOf.value.pageImage(PageIndex(48)).value.bytes[0] == 91
  let observed = workerInfo(worker).value
  assert observed.preparations == 1 and observed.hits == 1
  if selected == PvmBackend.Interpreted: assert observed.prepared.nativeOperations == 0
  # Positive asynchronous pure execution is qualified separately with a real runtime/worker barrier.
  assert observed.prepared.nativeOperations == 0 and current.value.backend == PvmBackend.Interpreted

when defined(pvmArm64Jit) and defined(arm64) and (defined(linux) or defined(macosx)):
  packageRuntimeWitness()

refinementWitness(PvmBackend.Interpreted)
refinementWitness(PvmBackend.Jit)
accumulationWitness(PvmBackend.Interpreted)
accumulationWitness(PvmBackend.Jit)
checkedMemoryWitness(PvmBackend.Interpreted)
checkedMemoryWitness(PvmBackend.Jit)
echo "PVM worker application passed"
