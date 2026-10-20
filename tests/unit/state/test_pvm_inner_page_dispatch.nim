# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_inner_page_dispatch_arc_release"}

## Genuine refinement bootstraps drive host-12 gas, protocol return codes and atomic normalized results.

import std/[assertions, syncio]
import ../../../src/state/[refinement_bootstrap, refinement_dispatch, refinement_outcome]
import ../../../src/pvm/[inner_machines, machine, step, refinement_exports]
import ../../../src/codec/[composite, work_digest]
import ../../support/[pvm_refinement_outcome, pvm_inner_lifecycle, arc_evidence]

proc limits(pages = 4'u32): RefinementInvocationLimits =
  ## Inner RAM allocation and all independent outer policies retain finite separately selected ceilings.
  result = refinementLimits()
  result.inner = innerLimits()
  result.inner.pages = PageLimit(pages)
proc fixture(mode: uint64, count = 1'u64, first = 16'u64, id = 0'u64,
    credit = 10000'u64): PreparedRefinementBootstrap =
  ## A literal embedded inner blob is created before the real guest's requested page operation.
  refinementFixture([refinementImmediate(7, 196608), refinementImmediate(8, 6),
    refinementImmediate(9, 0), @[10'u8, 9], refinementImmediate(7, id),
    refinementImmediate(8, first), refinementImmediate(9, count), refinementImmediate(10, mode),
    @[10'u8, 12], @[50'u8, 0]], credit = credit, writable = innerBlob())
proc run(source: PreparedRefinementBootstrap, cap = limits()): RefinementInvocationResult[
    RefinementInvocation] =
  ## Use the original authenticated bootstrap; no terminal machine or gas tuple can be substituted.
  runRefinementInvocation(source, [], refinementInputs(), ExportOffset(7), cap)
proc raw(source: PreparedRefinementBootstrap, cap = limits()): RefinementDispatchResult[
    RefinementOutcome] =
  ## Read actual response registers using only the bootstrap's own captured host environment.
  let prepared = source.bootstrapHosts([], refinementInputs(), ExportOffset(7), cap.capture).value
  executeRefinement(prepared, cap.copy, cap.exports, cap.steps, cap.calls, cap.cycles, cap.inner)
for row in [(0'u64, 330'u64), (1'u64, 396'u64), (2'u64, 396'u64),
    (3'u64, 159'u64), (4'u64, 159'u64), (99'u64, 80'u64)]:
  let source = fixture(row[0])
  let actual = raw(source).value
  assert actual.outcome.exit == StepExit.Halt
  assert uint64(actual.outcome.machine.machineInfo.value.registers[7]) ==
    (if row[0] > 2: high(uint64)-8 else: 0'u64) # Preserve modes see inaccessible RAM and return HUH.
  let normalized = run(source).value.refinementInfo.value
  assert normalized.kind == WorkKind.Success
  assert uint64(normalized.gasUsed) == refinementPrice(source)+1863+row[
      1] # Literal host prices plus separately verified pipeline cost.
# WHO precedes HUH, while host OOG retains exact debt and becomes a protocol work result.
let missing = fixture(99, first = high(uint64), id = high(uint64))
assert uint64(raw(missing).value.outcome.machine.machineInfo.value.registers[7]) == high(uint64)-3
let starved = fixture(2, credit = 2000)
let stopped = raw(starved).value.outcome
assert stopped.exit == StepExit.OutOfGas
assert uint64(stopped.machine.machineInfo.value.gasDeficit) == refinementPrice(
    starved)+1863+396-2000
assert run(starved).value.refinementInfo.value.kind == WorkKind.OutOfGas
assert uint64(run(starved).value.refinementInfo.value.gasUsed) == 2000
# Local page-capacity and gas-representation refusals expose no normalized owner or partial metadata.
let source = fixture(2)
var noCopy = limits()
noCopy.copy = MemoryByteLimit(0)
assert run(source, noCopy).error == RefinementInvocationError.None # Inner mapping is independent of outer fetch/lookup copy policy.
let capacity = run(source, limits(0))
assert capacity.error == RefinementInvocationError.HostFailure
assert capacity.hostError == RefinementDispatchError.LimitExceeded
let huge = run(fixture(2, count = high(uint64)))
assert huge.error == RefinementInvocationError.HostFailure
assert huge.hostError == RefinementDispatchError.LimitExceeded
# Creation, allocation and deletion compose without damaging caller RAM; every replay starts with a fresh map.
let composed = refinementFixture([refinementImmediate(7, 196608), refinementImmediate(8, 6),
  refinementImmediate(9, 0), @[10'u8, 9], refinementImmediate(8, 16),
  refinementImmediate(9, 1), refinementImmediate(10, 2), @[10'u8, 12], @[10'u8, 14],
  refinementImmediate(7, 196608), refinementImmediate(8, 6), @[50'u8, 0]], writable = innerBlob())
for replay in 0..<2:
  let done = run(composed).value
  assert done.refinementInfo.value.kind == WorkKind.Success
  assert done.refinementOutput.value == innerBlob() # Caller program bytes survive every host response.
# Fresh complete source/host/map/output generations and local-refusal scratch owners release together.
proc cycle() =
  ## Each iteration constructs its own genuine bootstrap and drops all retained owners on return.
  let fresh = fixture(2)
  assert run(fresh).value.refinementInfo.value.kind == WorkKind.Success
  assert run(fresh, limits(0)).error == RefinementInvocationError.HostFailure
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_inner_page_dispatch", 1000, before, after)
echo "PVM inner page dispatch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
