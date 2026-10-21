# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reserve and execute an authenticated assurance-fed queue under its retained original parameter authority.

import ../chain/parameters
import ./[assured_queue, accumulation_round, accumulation_runner, accumulation_execution]

type
  AssuredExecutionConfig* = object ## Semantic gas remains original while independent round and runner ceilings bound work.
    round*: AccumulationRoundConfig
    runner*: AccumulationRunnerLimits
  AssuredExecutionError* {.pure.} = enum ## Refusals expose no partial round or earlier completed service.
    Uninitialized, None, InvalidSource, ProfileMismatch, RoundFailure, RunnerFailure
  AssuredExecutionData = ref object ## Immutable acyclic ownership retains assurance source and the actual completed initial batch.
    source: AssuredAccumulationQueue
    completed: CompletedBlockAccumulation
  ExecutedAssuredAccumulation* = object ## Execution certification does not finalize, compose or publish successor state.
    data: nil AssuredExecutionData
  AssuredExecutionResult*[T] = object ## Only selected complete success or the genuine refused maintained phase can be inspected.
    case status: AssuredExecutionError
    of None: completed: T
    of RoundFailure: roundReason: AccumulationRoundResult[BlockAccumulationRound]
    of RunnerFailure: runnerReason: AccumulationRunnerResult
    else: discard # Defaults and source/profile refusals retain reasons alone.

func error*[T](outcome: AssuredExecutionResult[T]): AssuredExecutionError =
  ## Observe selection without writable discriminator access.
  outcome.status
func value*[T](outcome: AssuredExecutionResult[T]): T {.requires: outcome.status ==
    AssuredExecutionError.None.} =
  ## Extract only complete success under checked optimized contracts.
  outcome.completed
func roundFailure*[T](outcome: AssuredExecutionResult[T]): AccumulationRoundResult[
    BlockAccumulationRound] {.requires: outcome.status == AssuredExecutionError.RoundFailure.} =
  ## Preserve the actual failed initial-round planner without an earlier accepted prefix.
  outcome.roundReason
func runnerFailure*[T](outcome: AssuredExecutionResult[
    T]): AccumulationRunnerResult {.requires: outcome.status ==
    AssuredExecutionError.RunnerFailure.} =
  ## Preserve every nested actual runner refusal and its independently guarded payloads.
  outcome.runnerReason
proc assuredExecutionSource*(execution: ExecutedAssuredAccumulation): AssuredExecutionResult[
    AssuredAccumulationQueue] =
  ## Share exact assurance, admission and queue authority after caller handles retire.
  let data = execution.data
  if data == nil: return AssuredExecutionResult[AssuredAccumulationQueue](
      status: AssuredExecutionError.Uninitialized)
  AssuredExecutionResult[AssuredAccumulationQueue](status: AssuredExecutionError.None,
      completed: data.source)
proc assuredExecutionCompleted*(execution: ExecutedAssuredAccumulation): AssuredExecutionResult[
    CompletedBlockAccumulation] =
  ## Retain the genuine completed engine/batch certificate rather than copied terminal observations.
  let data = execution.data
  if data == nil: return AssuredExecutionResult[CompletedBlockAccumulation](
      status: AssuredExecutionError.Uninitialized)
  AssuredExecutionResult[CompletedBlockAccumulation](status: AssuredExecutionError.None,
      completed: data.completed)
proc assuredExecutionParameters*(execution: ExecutedAssuredAccumulation): AssuredExecutionResult[Parameters] =
  ## Copy all original parameters for inspection; callers cannot replace execution authority.
  let data = execution.data
  if data == nil: return AssuredExecutionResult[Parameters](
      status: AssuredExecutionError.Uninitialized)
  AssuredExecutionResult[Parameters](status: AssuredExecutionError.None,
      completed: data.source.assuredQueueParameters.value)
proc executeAssuredAccumulation*(source: AssuredAccumulationQueue,
    config: AssuredExecutionConfig): AssuredExecutionResult[ExecutedAssuredAccumulation] =
  ## Bind original semantic gas, reserve actual priority and execute once; publish no state or partial success on refusal.
  let queue = source.assuredQueuePlan
  if queue.error != AssuredQueueError.None:
    return AssuredExecutionResult[ExecutedAssuredAccumulation](
        status: AssuredExecutionError.InvalidSource) # A default owner supplies neither an empty queue nor parameters.
  let params = source.assuredQueueParameters.value
  let sameReportGas = uint64(config.round.reportGas) == params.get(maxAccumulateGas)
  let sameBlockGas = uint64(config.round.blockGas) == params.get(blockGasLimit)
  if not sameReportGas or not sameBlockGas:
    return AssuredExecutionResult[ExecutedAssuredAccumulation](
        status: AssuredExecutionError.ProfileMismatch) # Independent ceilings cannot alter protocol reservation semantics.
  let planned = planBlockInitialAccumulation(queue.value, config.round)
  if planned.error != AccumulationRoundError.None:
    return AssuredExecutionResult[ExecutedAssuredAccumulation](
        status: AssuredExecutionError.RoundFailure,
        roundReason: planned) # No earlier privilege or operand prefix escapes.
  let executed = runBlockAccumulation(planned.value, params, config.runner)
  if executed.error != AccumulationRunnerError.None:
    return AssuredExecutionResult[ExecutedAssuredAccumulation](
        status: AssuredExecutionError.RunnerFailure,
        runnerReason: executed) # A completed earlier service never substitutes for complete coverage.
  AssuredExecutionResult[ExecutedAssuredAccumulation](status: AssuredExecutionError.None,
    completed: ExecutedAssuredAccumulation(data: AssuredExecutionData(source: source,
        completed: executed.value)))
