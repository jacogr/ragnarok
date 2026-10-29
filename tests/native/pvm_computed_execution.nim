# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict actual computed execution/result-cause probes retain a real paid guest as their positive control.

import std/[assertions, cmdline]
import ../../src/state/computed/[execution as computed_execution, round as computed_round]
import ../../src/state/accumulation/[runner as accumulation_runner,
    execution as accumulation_execution, dispatch as accumulation_dispatch]
import ../../src/codec/bounded
import ../../src/pvm/step
import ../support/pvm_computed_execution

proc expect[T](outcome: ComputedExecutionResult[T], reason: ComputedExecutionError) =
  ## Confirm exact selection before deliberate missing successful value or unrelated cause extraction.
  assert outcome.error == reason, "computed execution runtime control"
let source = computedExecutionFixture()
let limits = computedExecutionLimits()
let done = executeComputedAccumulation(source, limits)
expect(done, ComputedExecutionError.None)
assert uint64(done.value.computedExecutionCompleted.value.executionInfo.value.gasUsed) > 0
let invalid = executeComputedAccumulation(default(ComputedAccumulationRound), limits)
expect(invalid, ComputedExecutionError.InvalidSource)
var changed = limits
changed.completion.services = ElementLimit(0)
let serviceLimit = executeComputedAccumulation(source, changed)
expect(serviceLimit, ComputedExecutionError.RunnerFailure)
assert serviceLimit.runnerFailure.error == AccumulationRunnerError.LimitExceeded
changed = limits
changed.steps = ExecutionStepLimit(0)
let engine = executeComputedAccumulation(source, changed)
expect(engine, ComputedExecutionError.RunnerFailure)
assert engine.runnerFailure.error == AccumulationRunnerError.DispatchFailure
assert engine.runnerFailure.dispatchFailure.executionError == StepError.StepLimitExceeded
let missing = default(ComputedExecutionResult[ExecutedComputedAccumulation])
case paramStr(1)
of "default": discard missing.value # Default owns no completed service execution.
of "source": discard invalid.value # No loose round/source authority.
of "limit": discard serviceLimit.value # Resource refusal exposes no batch prefix.
of "engine": discard engine.value # Exact engine refusal exposes no completed result.
of "owner": discard default(ExecutedComputedAccumulation).computedExecutionSource.value # No retained computation graph.
of "completed": discard default(ExecutedComputedAccumulation).computedExecutionCompleted.value # No terminal/gas certificate.
of "reason-default": discard missing.runnerFailure # Default contains no nested runner refusal.
of "reason-success": discard done.runnerFailure # Completed success contains no failure.
else: discard invalid.runnerFailure # Ordinary invalid-source refusal has no unrelated child cause.
