# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_inner_transfer_dispatch_arc_release"}

## Genuine refinement guests compose creation/pages/poke/peek with normalized bytes, gas and typed local refusals.

import std/[assertions, syncio]
import ../../../src/state/[refinement_bootstrap, refinement_dispatch, refinement_outcome]
import ../../../src/pvm/[inner_machines, machine, step, refinement_exports]
import ../../../src/codec/[composite, work_digest]
import ../../support/[pvm_refinement_outcome, pvm_inner_lifecycle, arc_evidence]

proc limits(): RefinementInvocationLimits =
  ## Every independent capture, engine, output and copy policy stays finite beside inner page/program budgets.
  result = refinementLimits()
  result.inner = innerLimits()
  result.calls = HostCallLimit(5) # Compile and instantiate are now distinct calls before pages/poke/peek.
proc fixture(credit = 10000'u64): PreparedRefinementBootstrap =
  ## Authored compact compile/instantiate arguments keep this real guest below the small fixture's 128-byte code bound.
  ## The final host copies into a distinct caller address, so returning original input cannot satisfy the witness.
  refinementFixture(refinementInnerCreate(suffix = @[refinementImmediate(8, 16),
      refinementImmediate(9, 1), refinementImmediate(10, 2),
    @[10'u8, 13], refinementImmediate(8, 196608), refinementImmediate(9, 65536),
    refinementImmediate(10, 6), @[10'u8, 12], refinementImmediate(8, 196672), @[10'u8, 11],
    refinementImmediate(7, 196672), refinementImmediate(8, 6), @[50'u8, 0]]),
    credit = credit, writable = innerBlob())
proc run(source: PreparedRefinementBootstrap, cap = limits()): RefinementInvocationResult[
    RefinementInvocation] =
  ## Execute the exact bootstrap source; callers supply no independent terminal machine or gas/export tuples.
  runRefinementInvocation(source, [], refinementInputs(), ExportOffset(7), cap)
proc raw(source: PreparedRefinementBootstrap, cap = limits()): RefinementDispatchResult[
    RefinementOutcome] =
  ## Inspect actual stopped gas/registers while retaining that same source's captured host environment.
  let captured = source.bootstrapHosts([], refinementInputs(), ExportOffset(7), cap.capture).value
  executeRefinement(captured, cap.copy, cap.exports, cap.steps, cap.calls, cap.cycles, cap.inner)
let source = fixture()
for replay in 0..<2:
  let done = run(source).value
  assert done.refinementOutput.value == @[0'u8, 0, 2, 50, 0, 1]
  assert done.refinementInfo.value.kind == WorkKind.Success
  assert uint64(done.refinementInfo.value.exports) == 0
  assert uint64(done.refinementInfo.value.gasUsed) == refinementPrice(
      source)+4800 # Literal compile 1864 + machine 1862 + pages 396 + poke 379 + peek 299.
  let original = source.bootstrapMachine.value.memoryOf.value
  assert original.readBytes(MemoryAddress(196672), MemoryLength(6), MemoryByteLimit(6)).value == @[
      0'u8, 0, 0, 0, 0, 0]
var capped = limits()
capped.copy = MemoryByteLimit(5)
let refused = run(source, capped)
assert refused.error == RefinementInvocationError.HostFailure
assert refused.hostError == RefinementDispatchError.LimitExceeded
capped = limits()
capped.calls = HostCallLimit(3)
let engine = run(source, capped)
assert engine.error == RefinementInvocationError.ExecutionFailure
assert engine.executionError == StepError.HostCallLimitExceeded # Local host-count exhaustion cannot become protocol OOG.
let starved = fixture(2700)
let stopped = raw(starved).value.outcome
assert stopped.exit == StepExit.OutOfGas
assert uint64(stopped.machine.machineInfo.value.gasDeficit) == 0
assert run(starved).value.refinementInfo.value.kind == WorkKind.OutOfGas
assert uint64(run(starved).value.refinementInfo.value.gasUsed) == 2700
# A caller write to read-only memory is protocol panic before WHO; absent inner IDs on valid caller ranges return WHO.
let panic = refinementFixture([refinementImmediate(7, high(uint64)), refinementImmediate(8, 65536),
  refinementImmediate(9, 0), refinementImmediate(10, 1), @[10'u8, 11], @[50'u8, 0]])
assert run(panic).value.refinementInfo.value.kind == WorkKind.Panic
let who = refinementFixture([refinementImmediate(7, high(uint64)), refinementImmediate(8, 65536),
  refinementImmediate(9, high(uint64)), refinementImmediate(10, 1), @[10'u8, 12], @[50'u8, 0]])
assert uint64(raw(who).value.outcome.machine.machineInfo.value.registers[7]) == high(uint64)-3
assert run(who).value.refinementInfo.value.kind == WorkKind.Success
# Invocation-local maps and all page/output generations disappear after each independent real-bootstrap run.
proc cycle() =
  ## Fresh source captures and local-refusal scratch owners must both release before the next ARC measurement.
  let fresh = fixture()
  let completed = run(fresh).value
  assert completed.refinementOutput.value == innerBlob()
  var cap = limits()
  cap.copy = MemoryByteLimit(0)
  assert run(fresh, cap).error == RefinementInvocationError.HostFailure
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_inner_transfer_dispatch", 1000, before, after)
echo "PVM inner transfer dispatch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
