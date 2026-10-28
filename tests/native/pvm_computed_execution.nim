# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict actual computed execution/result-cause probes retain a real paid guest as their positive control.

import std/assertions
import std/cmdline
import ../../src/state/computed_execution as state_computed_execution
import ../../src/state/computed_round as state_computed_round
import ../../src/state/accumulation_runner as state_accumulation_runner
import ../../src/state/accumulation_execution as state_accumulation_execution
import ../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../src/codec/bounded as codec_bounded
import ../../src/pvm/step as pvm_step
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
