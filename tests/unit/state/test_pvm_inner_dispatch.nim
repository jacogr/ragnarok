# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_inner_dispatch_arc_release"}

## Genuine bootstraps run lifecycle calls with replay isolation, exact provenance and atomic local refusal.

import std/[assertions, syncio]
import ../../../src/state/[refinement_bootstrap, refinement_dispatch, refinement_outcome]
import ../../../src/pvm/[inner_machines, machine, step, refinement_exports]
import ../../../src/codec/[composite, work_digest]
import ../../support/[pvm_refinement_outcome, pvm_inner_lifecycle, arc_evidence]

proc limits(): RefinementInvocationLimits =
  ## Enable finite inner storage without changing any independent capture/execution/output policy.
  result = refinementLimits()
  result.inner = innerLimits()
proc run(source: PreparedRefinementBootstrap, cap = limits()): RefinementInvocationResult[
    RefinementInvocation] =
  ## Invoke the public source-bound runner; no independently replaceable CPU or terminal tuple is supplied.
  runRefinementInvocation(source, [], refinementInputs(), ExportOffset(7), cap)
proc raw(source: PreparedRefinementBootstrap, cap = limits()): RefinementDispatchResult[
    RefinementOutcome] =
  ## Inspect actual host registers through the lower dispatcher, using that bootstrap's own captured environment.
  let captured = source.bootstrapHosts([], refinementInputs(), ExportOffset(7), cap.capture).value
  executeRefinement(captured, cap.copy, cap.exports, cap.steps, cap.calls, cap.cycles, cap.inner)
let halt = @[50'u8, 0]
let source = refinementFixture([refinementImmediate(7, 196608), refinementImmediate(8, 6),
  refinementImmediate(9, 0), @[10'u8, 9], @[10'u8, 14], halt], writable = innerBlob())
for replay in 0..<2:
  let done = raw(source).value
  assert done.outcome.exit == StepExit.Halt
  assert uint64(done.outcome.machine.machineInfo.value.registers[7]) ==
      0 # Delete returns the genuine created entry PC.
  let normalized = run(source).value.refinementInfo.value
  assert normalized.kind == WorkKind.Success and uint64(normalized.exports) == 0
  assert uint64(normalized.gasUsed) >= 2198 # Literal lifecycle prices; instruction pricing adds independently.
# Repeated create finds zero, proving each separate run starts empty even when a previous guest retained its machine.
let retain = refinementFixture([refinementImmediate(7, 196608), refinementImmediate(8, 6),
  refinementImmediate(9, 0), @[10'u8, 9], halt], writable = innerBlob())
for replay in 0..<2:
  assert uint64(raw(retain).value.outcome.machine.machineInfo.value.registers[7]) == 0
let absent = refinementFixture([refinementImmediate(7, 0), @[10'u8, 14], halt])
assert uint64(raw(absent).value.outcome.machine.machineInfo.value.registers[7]) == high(uint64)-3
# Creation at a nonzero valid entry is reflected by expunge, rather than replaced by a fabricated default PC.
let nonzero = refinementFixture([refinementImmediate(7, 196608), refinementImmediate(8, 7),
  refinementImmediate(9, 1), @[10'u8, 9], @[10'u8, 14], halt],
  writable = @[0'u8, 0, 3, 1, 50, 0, 3])
assert uint64(raw(nonzero).value.outcome.machine.machineInfo.value.registers[7]) == 1
# Local inner allocation policies are refusals without normalized output, gas metadata or export leakage.
for policy in 0..<3:
  var cap = limits()
  case policy
  of 0: cap.inner.items = InnerMachineLimit(0) # Distinct local count budget cannot fabricate protocol FULL.
  of 1: cap.inner.total = InnerProgramLimit(5)
  else: cap.copy = MemoryByteLimit(0) # Host 9 has its own program-copy budget, separate from fetch/lookup copy.
  let outcome = run(source, cap)
  if policy < 2:
    assert outcome.error == RefinementInvocationError.HostFailure
    assert outcome.hostError == RefinementDispatchError.LimitExceeded
  else:
    assert outcome.error == RefinementInvocationError.None
# Invalid deblob is a charged HUH response; unreadability is protocol panic, both distinct from local refusal.
let invalid = refinementFixture([refinementImmediate(7, 196608), refinementImmediate(8, 3),
  refinementImmediate(9, 0), @[10'u8, 9], halt])
assert uint64(raw(invalid).value.outcome.machine.machineInfo.value.registers[7]) == high(uint64)-8
let panic = refinementFixture([refinementImmediate(7, high(uint64)), refinementImmediate(8, 6),
  @[10'u8, 9], halt])
assert run(panic).value.refinementInfo.value.kind == WorkKind.Panic
let starved = refinementFixture([refinementImmediate(7, 196608), refinementImmediate(8, 6),
  @[10'u8, 9], halt], credit = 100, writable = innerBlob())
assert run(starved).value.refinementInfo.value.kind == WorkKind.OutOfGas
# Fresh bootstraps, captured environments, inner maps and local-failure scratch runs all release under ARC.
proc cycle() =
  ## Do not retain source or output handles across independent lifetime iterations.
  let fresh = refinementFixture([refinementImmediate(7, 196608), refinementImmediate(8, 6),
    refinementImmediate(9, 0), @[10'u8, 9], @[10'u8, 14], halt], writable = innerBlob())
  assert run(fresh).value.refinementInfo.value.kind == WorkKind.Success
  var cap = limits()
  cap.inner.items = InnerMachineLimit(0)
  assert run(fresh, cap).error == RefinementInvocationError.HostFailure
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_inner_dispatch", 1000, before, after)
echo "PVM inner dispatch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
