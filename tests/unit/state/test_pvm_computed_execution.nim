# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_computed_execution_arc_release"}

## Genuine historical service execution retains original computed parameters and never fabricates engine outcomes.

import std/[assertions, syncio]
import ../../../src/state/[computed_execution, computed_round, computed_publication,
  computed_admission, report_admission, accumulation_runner, accumulation_execution,
  accumulation_round, accumulation_queue, accumulation_inputs, accumulation_batch,
  accumulation_outcome,
  accumulation_provisions, block_transition, block_admission,
  store]
import ../../../src/state/accumulation_dispatch
import ../../../src/pvm/step
import ../../../src/codec/bounded
import ../../support/[pvm_computed_execution, arc_evidence]

proc expect[T](outcome: ComputedExecutionResult[T], reason: ComputedExecutionError) =
  ## Print exact original runner stage on unexpected refusal, then enforce selected result behavior.
  if outcome.error != reason:
    echo "expected ", reason, " got ", outcome.error # Keep successful output exact while retaining actionable failures.
    if outcome.error == ComputedExecutionError.RunnerFailure:
      let child = outcome.runnerFailure
      echo "runner ", child.error
      if child.error == AccumulationRunnerError.ContextFailure: echo "context ", child.contextError
      if child.error == AccumulationRunnerError.MachineFailure: echo "machine ", child.machineError
      if child.error == AccumulationRunnerError.DispatchFailure: echo "dispatch ",
          child.dispatchFailure.error
  assert outcome.error == reason, "computed execution reason"
let source = computedExecutionFixture()
let limits = computedExecutionLimits()
let outcome = executeComputedAccumulation(source, limits)
expect(outcome, ComputedExecutionError.None)
let done = outcome.value
let completed = done.computedExecutionCompleted.value
let info = completed.executionInfo.value
assert info.services == 1 and uint64(info.round.prefix) == 1
assert info.batch.executions == 1 and info.batch.skipped == 0 and info.batch.completeInputs
assert info.batch.stagingWrites == 0 and info.batch.assignmentWrites == 0
assert info.batch.selfWrites == 0 and info.batch.deletedAccounts == 0 and
    info.batch.createdAccounts == 0
let terminal = completed.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(
    0)).value.outcomeInfo.value
assert terminal.termination == AccumulationTermination.Halt and not terminal.hasYield
assert terminal.transfers == 0 and terminal.provisions == 0
assert uint64(info.gasUsed) > 0 and uint64(info.gasUsed) <= 100
var copiedInfo = completed.executionInfo.value
copiedInfo.services = 0
copiedInfo.gasUsed = typeof(copiedInfo.gasUsed)(0)
var copiedCompleted = done.computedExecutionCompleted.value
copiedCompleted = default(CompletedBlockAccumulation)
var copiedSource = done.computedExecutionSource.value
copiedSource = default(ComputedAccumulationRound)
assert done.computedExecutionCompleted.value.executionInfo.value.services == 1
assert uint64(done.computedExecutionCompleted.value.executionInfo.value.gasUsed) > 0
assert done.computedExecutionSource.value.computedRoundPlan.error == ComputedRoundError.None
let usage = completed.executionGasAt(InvocationServiceIndex(0)).value
assert uint32(usage.service) == 42 and uint64(usage.gasUsed) == uint64(info.gasUsed)
let original = source.computedRoundPlan.value.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedState
let retained = completed.executionRound.value.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedState
assert sameStateSnapshot(original, retained), "actual execution retains exact original parent"
assert done.computedExecutionSource.value.computedRoundParameters.value ==
    source.computedRoundParameters.value
let emptySource = computedExecutionFixture(withReady = false)
let empty = executeComputedAccumulation(emptySource, limits)
expect(empty, ComputedExecutionError.None)
assert empty.value.computedExecutionCompleted.value.executionInfo.value.services == 0
assert uint64(empty.value.computedExecutionCompleted.value.executionInfo.value.gasUsed) == 0
let missingCodeContext = computedExecutionFixture(withExecution = false)
let refused = executeComputedAccumulation(missingCodeContext, limits)
expect(refused, ComputedExecutionError.RunnerFailure)
assert refused.runnerFailure.error == AccumulationRunnerError.ContextFailure
let invalidEntry = computedExecutionFixture(invalidEntry = true)
let badEntry = executeComputedAccumulation(invalidEntry, limits)
expect(badEntry, ComputedExecutionError.RunnerFailure)
assert badEntry.runnerFailure.error == AccumulationRunnerError.MachineFailure
expect(executeComputedAccumulation(default(ComputedAccumulationRound), limits),
    ComputedExecutionError.InvalidSource)
var short = limits
short.completion.services = ElementLimit(0)
let serviceLimit = executeComputedAccumulation(source, short)
expect(serviceLimit, ComputedExecutionError.RunnerFailure)
assert serviceLimit.runnerFailure.error == AccumulationRunnerError.LimitExceeded
short = limits
short.steps = typeof(short.steps)(0)
let engineLimit = executeComputedAccumulation(source, short)
expect(engineLimit, ComputedExecutionError.RunnerFailure)
assert engineLimit.runnerFailure.error == AccumulationRunnerError.DispatchFailure
assert engineLimit.runnerFailure.dispatchFailure.error == AccumulationDispatchError.ExecutionFailure
assert engineLimit.runnerFailure.dispatchFailure.executionError == StepError.StepLimitExceeded
expect(default(ExecutedComputedAccumulation).computedExecutionSource,
    ComputedExecutionError.Uninitialized)
expect(default(ExecutedComputedAccumulation).computedExecutionCompleted,
    ComputedExecutionError.Uninitialized)
proc detached(): ExecutedComputedAccumulation =
  ## Retain actual terminal/gas/source owners after every caller's original fixture and policy retires.
  executeComputedAccumulation(computedExecutionFixture(), computedExecutionLimits()).value
let held = detached()
assert held.computedExecutionCompleted.value.executionInfo.value.services == 1
proc cycle(source: ComputedAccumulationRound, limits: AccumulationRunnerLimits) =
  ## Execute and release actual service contexts, machine snapshots, completed batch and source sharing.
  let value = executeComputedAccumulation(source, limits).value
  discard value.computedExecutionSource.value
  discard value.computedExecutionCompleted.value.executionInfo.value
cycle(source, limits)
let before = getOccupiedMem()
for i in 0..<1000: cycle(source, limits) # Actual guest execution and complete certified batches retire each iteration.
let after = getOccupiedMem()
assert before == after, "computed execution ARC release"
recordArcRelease("pvm_computed_execution", 1000, before, after)
echo "PVM computed execution passed"
echo "ARC_RELEASE cycles=1000 unchanged"
