# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_computed_finalization_arc_release"}

## Genuine n=0 continuation finalizes actual computed execution without replaying initial guests or losing pending-report provenance.

import std/[assertions, syncio]
import ../../../src/state/[computed_finalization, computed_execution, computed_round,
  computed_publication, computed_admission, report_admission, block_transition, block_admission,
  accumulation_driver, accumulation_finalization, accumulation_outputs, accumulation_execution,
  accumulation_continuation, store]
import ../../../src/codec/[bounded, state_layout]
import ../../../src/pvm/step
import ../../support/[pvm_computed_finalization, arc_evidence]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Force genuine private map/root work to fail after actual service execution completes.
proc expect[T](outcome: ComputedFinalizationResult[T], reason: ComputedFinalizationError) =
  ## Print the exact selected originating stage on unexpected refusal before enforcing application extraction contracts.
  if outcome.error != reason:
    echo "expected ", reason, " got ", outcome.error
    if outcome.error == ComputedFinalizationError.DriverFailure: echo "driver ",
        outcome.driverFailure.error
    if outcome.error == ComputedFinalizationError.FinalizationFailure: echo "finalizer ",
        outcome.finalizationFailure.error
  assert outcome.error == reason, "computed finalization reason"
let source = finalizationFixture()
let config = computedFinalizationConfig()
let completed = source.computedExecutionCompleted.value
let paid = uint64(completed.executionInfo.value.gasUsed)
let result = finalizeComputedAccumulation(source, config)
expect(result, ComputedFinalizationError.None)
let done = result.value
assert done.computedFinalizationStopped.value.stoppedKind == StoppedAccumulationKind.Continuation
let final = done.computedFinalizationPlan.value
let facts = final.finalAccumulationInfo.value
assert uint64(facts.completedPrefix) == 1 and facts.pendingReports == 0
assert uint64(facts.remainingGas) == 1000000-paid
assert facts.outputs.rounds == 2 and facts.outputs.executions == 1
assert facts.outputs.outputs == 0 and facts.outputs.encodedBytes == 1
assert final.finalAccumulationState.value.lookup(chapterKey(StateChapter(16))).value.bytes == @[0'u8]
let original = source.computedExecutionSource.value.computedRoundSource.value.computedSuccessorSource.value.computedAdmissionReports.value.reportBlockStage.value.value.admitted.admittedState
assert sameStateSnapshot(final.finalAccumulationParent.value, original)
let pending = source.computedExecutionSource.value.computedRoundSource.value.computedSuccessorSnapshot.value
assert done.computedFinalizationSource.value.computedExecutionSource.value.computedRoundSource.value.computedSuccessorSnapshot.value.lookup(
    chapterKey(StateChapter(10))).value.bytes == pending.lookup(chapterKey(StateChapter(
    10))).value.bytes
var idle = config
idle.driver.execution.steps = ExecutionStepLimit(0)
expect(finalizeComputedAccumulation(source, idle), ComputedFinalizationError.None)
let emptySource = finalizationFixture(withReady = false)
let empty = finalizeComputedAccumulation(emptySource, config)
expect(empty, ComputedFinalizationError.None)
assert uint64(empty.value.computedFinalizationPlan.value.finalAccumulationInfo.value.completedPrefix) == 0
assert uint64(empty.value.computedFinalizationPlan.value.finalAccumulationInfo.value.remainingGas) == 1000000
expect(finalizeComputedAccumulation(default(ExecutedComputedAccumulation), config),
    ComputedFinalizationError.InvalidSource)
var short = config
short.driver.preparation.selection.executions = ElementLimit(0)
let driver = finalizeComputedAccumulation(source, short)
expect(driver, ComputedFinalizationError.DriverFailure)
assert driver.driverFailure.error == AccumulationDriverError.SelectionFailure
short = config
short.outputs.rounds = ElementLimit(1)
let history = finalizeComputedAccumulation(source, short)
expect(history, ComputedFinalizationError.FinalizationFailure)
assert history.finalizationFailure.error == AccumulationFinalizationError.OutputFailure
assert history.finalizationFailure.outputError == AccumulationOutputsError.LimitExceeded
short = config
short.outputs.log.maxBytes = ByteLimit(0)
expect(finalizeComputedAccumulation(source, short), ComputedFinalizationError.FinalizationFailure)
reset(1)
let refusal = finalizeComputedAccumulation(source, config)
expect(refusal, ComputedFinalizationError.FinalizationFailure)
assert refusal.finalizationFailure.error == AccumulationFinalizationError.StateFailure
assert refusal.finalizationFailure.stateError == StateStoreError.BackendFailure
reset(0)
assert sameStateSnapshot(final.finalAccumulationParent.value, original)
var copied = done.computedFinalizationPlan.value
copied = default(PreparedFinalAccumulation)
assert done.computedFinalizationPlan.value.finalAccumulationInfo.value.outputs.rounds == 2
expect(default(FinalizedComputedAccumulation).computedFinalizationSource,
    ComputedFinalizationError.Uninitialized)
expect(default(FinalizedComputedAccumulation).computedFinalizationStopped,
    ComputedFinalizationError.Uninitialized)
expect(default(FinalizedComputedAccumulation).computedFinalizationPlan,
    ComputedFinalizationError.Uninitialized)
proc detached(): FinalizedComputedAccumulation =
  ## Retain all actual execution/stop/final-map authority after caller fixture owners retire.
  finalizeComputedAccumulation(finalizationFixture(), computedFinalizationConfig()).value
let held = detached()
assert held.computedFinalizationPlan.value.finalAccumulationInfo.value.pendingReports == 0
proc cycle(source: ExecutedComputedAccumulation, config: ComputedFinalizationConfig) =
  ## Prepare and release genuine idle continuation, output history and private C(16) successor every iteration.
  let final = finalizeComputedAccumulation(source, config).value
  discard final.computedFinalizationPlan.value.finalAccumulationState.value
  discard final.computedFinalizationStopped.value
  discard final.computedFinalizationSource.value
cycle(source, config)
let before = getOccupiedMem()
for i in 0..<1000: cycle(source, config) # No completed finalization history or map is retained across iterations.
let after = getOccupiedMem()
assert before == after, "computed finalization ARC release"
recordArcRelease("pvm_computed_finalization", 1000, before, after)
echo "PVM computed finalization passed"
echo "ARC_RELEASE cycles=1000 unchanged"
