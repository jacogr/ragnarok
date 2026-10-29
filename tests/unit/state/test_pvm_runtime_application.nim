# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual application invocations use the selected guest engine and ordinary Nim host dispatch.
## Each alternative preserves normalized outputs, gas, inner frame publication and immutable sources.
import std/[assertions, syncio]
import ../../../src/app/options
import ../../../src/state/authorization/invocation as authorization_invocation
import ../../../src/state/refinement/[outcome as refinement_outcome,
    dispatch as refinement_dispatch]
import ../../../src/state/accumulation/[dispatch as accumulation_dispatch,
    machine as accumulation_machine]
import ../../../src/pvm/[machine, step, gas, host_fetch, refinement_exports, inner_machines]
import ../../../src/codec/[bounded, c2_records]
import ../../../src/codec/work/[report as work_report, digest as work_digest]
import ../../support/[pvm_authorization_invoke, pvm_refinement_outcome,
    pvm_accumulation_context, pvm_accumulation_program, pvm_inner_lifecycle, pvm_inner_invoke]

proc witness(selected: PvmBackend) =
  ## Parse the public flag and pass its exact value into all supported application invocation families.
  var options = default(Options)
  assert parseOptions(@["--help", "--pvm-backend", $selected], options)
  assert options.pvmBackend == selected
  let halt = @[50'u8, 0]
  let returned = @[refinementImmediate(7, 196608), refinementImmediate(8, 3), halt]
  let fixture = authorizationFixture(returned)
  var auth = authorizationLimits()
  auth.backend = options.pvmBackend
  let authorized = authorizationRun(fixture, auth)
  assert authorized.error == AuthorizationInvocationError.None
  assert authorized.value.authorizationTrace.value == @[21'u8, 22, 23]
  # A gas host and fetch host run before returning the actual initialized writable output.
  let bootstrap = refinementFixture([@[10'u8, 0], @[10'u8, 2],
      refinementImmediate(7, 196608), refinementImmediate(8, 3), halt])
  var refine = refinementLimits()
  refine.backend = options.pvmBackend
  let refined = runRefinementInvocation(bootstrap, [], refinementInputs(), ExportOffset(0), refine)
  assert refined.error == RefinementInvocationError.None
  assert refined.value.refinementOutput.value == @[21'u8, 22, 23]
  let machine = guestProgram([@[10'u8, 0], @[10'u8, 2], halt])
  let fetch = FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
      operand: OperandLimits(maxBytes: ByteLimit(132)))
  let accumulated = executeAccumulationMachine(machine, pvmParameters(), fetch, MemoryByteLimit(0),
      ExecutionStepLimit(20), HostCallLimit(4), GasCycleLimit(1000), pvmContextConfig(),
          backend = options.pvmBackend)
  assert accumulated.error == AccumulationDispatchError.None
  assert accumulated.value.exit == StepExit.Halt and accumulated.value.backend == selected
  # The ordinary nested host publishes an actual segment receipt, independent of identical guest outputs.
  var nestedLimits = innerLimits()
  nestedLimits.backend = options.pvmBackend
  let machines = invokeMachines(cap = nestedLimits)
  assert not machines.innerMachine(InnerMachineId(0)).value.executed
  let invokedSegment = innerInvokeResponse(machines, MachineGas(10000), invokeArgs(), invokeMemory())
  assert invokedSegment.error == InnerMachineError.None
  let innerReceipt = invokedSegment.value.machines.innerMachine(InnerMachineId(0)).value
  assert innerReceipt.executed and innerReceipt.backend == selected
  # Compile/create/invoke a genuine inner halt program from original guest memory.
  var writable = newSeq[byte](368)
  let inner = [0'u8, 0, 2, 50, 0, 1]
  for index in 0..<inner.len: writable[index] = inner[index]
  writable[256] = 100 # E8 fuel for the nested segment.
  writable[266] = 255
  writable[267] = 255 # E8 register0 is the dynamic halt sentinel 0xffff0000.
  let instructions = refinementInnerCreate(suffix = @[
      refinementImmediate(8, 196864), @[10'u8, 14],
      refinementImmediate(7, 196864), refinementImmediate(8, 112), halt])
  let nested = refinementFixture(instructions, credit = 100000, writable = writable)
  refine.inner = innerLimits()
  refine.inner.backend = PvmBackend.PolkaCompiled # The outer selection must replace this conflicting inner policy.
  let invoked = runRefinementInvocation(nested, [], refinementInputs(), ExportOffset(0), refine)
  assert invoked.error == RefinementInvocationError.None
  let frame = invoked.value.refinementOutput.value
  assert frame.len == 112 and frame[0] < 100 and frame[0] > 0
  assert frame[10] == 255 and frame[11] == 255

witness(PvmBackend.Interpreted)
witness(PvmBackend.PolkaInterpreted)
stdout.writeLine("PASS application PVM backend selection")
