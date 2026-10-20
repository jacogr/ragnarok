# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict actual assured execution result guards with genuine success and precise maintained phase refusals.

import std/[assertions, cmdline]
import ../../src/state/[assured_execution, assured_queue, accumulation_execution,
    accumulation_round, accumulation_runner]
import ../../src/codec/bounded
import ../support/pvm_assured_execution

proc expect[T](outcome: AssuredExecutionResult[T], reason: AssuredExecutionError) =
  ## Verify selected alternatives without turning deliberate misuse into static contradictions.
  assert outcome.error == reason, "assured execution runtime control"
let source = assuredExecutionFixture()
let config = assuredExecutionConfig(source)
let done = executeAssuredAccumulation(source, config)
expect(done, AssuredExecutionError.None)
assert done.value.assuredExecutionCompleted.value.executionInfo.value.batch.executions == 1
assert uint64(done.value.assuredExecutionCompleted.value.executionInfo.value.round.prefix) == 2
let invalid = executeAssuredAccumulation(default(AssuredAccumulationQueue), config)
expect(invalid, AssuredExecutionError.InvalidSource)
var changed = config
changed.round.blockGas = typeof(changed.round.blockGas)(1)
let profile = executeAssuredAccumulation(source, changed)
expect(profile, AssuredExecutionError.ProfileMismatch)
changed = config
changed.round.operands.reports = ElementLimit(1)
let round = executeAssuredAccumulation(source, changed)
expect(round, AssuredExecutionError.RoundFailure)
assert round.roundFailure.error == AccumulationRoundError.LimitExceeded
changed = config
changed.runner.completion.batch.selfValueBytes = ByteLimit(2)
let runner = executeAssuredAccumulation(source, changed)
expect(runner, AssuredExecutionError.RunnerFailure)
assert runner.runnerFailure.error == AccumulationRunnerError.CompletionFailure
let missing = default(AssuredExecutionResult[ExecutedAssuredAccumulation])
case paramStr(1)
of "default": discard missing.value # Only selected complete success or the actual refused phase can be extracted.
of "source": discard invalid.value # Only selected complete success or the actual refused phase can be extracted.
of "profile": discard profile.value # Only selected complete success or the actual refused phase can be extracted.
of "round": discard round.value # Only selected complete success or the actual refused phase can be extracted.
of "runner": discard runner.value # Only selected complete success or the actual refused phase can be extracted.
of "owner": discard default(ExecutedAssuredAccumulation).assuredExecutionSource.value # Only selected complete success or the actual refused phase can be extracted.
of "completed": discard default(ExecutedAssuredAccumulation).assuredExecutionCompleted.value # Only selected complete success or the actual refused phase can be extracted.
of "parameters": discard default(ExecutedAssuredAccumulation).assuredExecutionParameters.value # Only selected complete success or the actual refused phase can be extracted.
of "roundFailure-default": discard missing.roundFailure # Only selected complete success or the actual refused phase can be extracted.
of "roundFailure-success": discard done.roundFailure # Only selected complete success or the actual refused phase can be extracted.
of "roundFailure-source": discard invalid.roundFailure # Only selected complete success or the actual refused phase can be extracted.
of "roundFailure-other": discard runner.roundFailure # Only selected complete success or the actual refused phase can be extracted.
of "runnerFailure-default": discard missing.runnerFailure # Only selected complete success or the actual refused phase can be extracted.
of "runnerFailure-success": discard done.runnerFailure # Only selected complete success or the actual refused phase can be extracted.
of "runnerFailure-source": discard invalid.runnerFailure # Only selected complete success or the actual refused phase can be extracted.
of "runnerFailure-other": discard round.runnerFailure # Only selected complete success or the actual refused phase can be extracted.
else: discard invalid.value # Unknown modes never become passing controls.
