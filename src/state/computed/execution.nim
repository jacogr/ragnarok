# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute genuine computed accumulation rounds using only their retained original parameter authority.

import ./round as computed_round
import ../accumulation/[runner as accumulation_runner, execution as accumulation_execution]

type
  ComputedExecutionError* {.pure.} = enum ## Only a selected actual runner failure carries its original typed refusal.
    Uninitialized, None, InvalidSource, RunnerFailure
  ComputedExecutionData = ref object ## Immutable acyclic ownership retains source round and fully completed execution certificates.
    source: ComputedAccumulationRound
    execution: CompletedBlockAccumulation
  ExecutedComputedAccumulation* = object ## Completed initial execution is not final state composition or block publication.
    data: nil ComputedExecutionData
  ComputedExecutionResult*[T] = object ## Defaults/refusals never retain a partially completed service batch.
    case status: ComputedExecutionError
    of None:
      completed: T
    of RunnerFailure:
      runnerReason: AccumulationRunnerResult
    else:
      discard # Ordinary refusals carry selected reasons alone.

func error*[T](outcome: ComputedExecutionResult[T]): ComputedExecutionError =
  ## Observe selection without granting writable discriminator access.
  outcome.status
func value*[T](outcome: ComputedExecutionResult[T]): T
    {.requires: outcome.status == ComputedExecutionError.None.} =
  ## Preserve complete-success extraction under optimized compilation.
  outcome.completed
func runnerFailure*[T](outcome: ComputedExecutionResult[T]): AccumulationRunnerResult
    {.requires: outcome.status == ComputedExecutionError.RunnerFailure.} =
  ## Retain only the actual refused runner result with all its existing nested guards.
  outcome.runnerReason
proc computedExecutionSource*(execution: ExecutedComputedAccumulation): ComputedExecutionResult[
    ComputedAccumulationRound] =
  ## Share exact original computed reports, published assignments, initial round and parameter authority.
  let data = execution.data
  if data == nil: return ComputedExecutionResult[ComputedAccumulationRound](
      status: ComputedExecutionError.Uninitialized)
  ComputedExecutionResult[ComputedAccumulationRound](status: ComputedExecutionError.None,
      completed: data.source)
proc computedExecutionCompleted*(execution: ExecutedComputedAccumulation): ComputedExecutionResult[
    CompletedBlockAccumulation] =
  ## Share the real completed engine result; copied observations cannot replace this certificate.
  let data = execution.data
  if data == nil: return ComputedExecutionResult[CompletedBlockAccumulation](
      status: ComputedExecutionError.Uninitialized)
  ComputedExecutionResult[CompletedBlockAccumulation](status: ComputedExecutionError.None,
      completed: data.execution)
proc executeComputedAccumulation*(source: ComputedAccumulationRound,
    limits: AccumulationRunnerLimits): ComputedExecutionResult[ExecutedComputedAccumulation] =
  ## Resolve and execute every selected service under original source parameters, publishing no partial success on refusal.
  let plan = source.computedRoundPlan
  if plan.error != ComputedRoundError.None:
    return ComputedExecutionResult[ExecutedComputedAccumulation](
        status: ComputedExecutionError.InvalidSource)
  let executed = runBlockAccumulation(plan.value, source.computedRoundParameters.value, limits)
  if executed.error != AccumulationRunnerError.None:
    return ComputedExecutionResult[ExecutedComputedAccumulation](
      status: ComputedExecutionError.RunnerFailure,
      runnerReason: executed) # Every original service/engine/context/completion refusal remains selected and typed.
  ComputedExecutionResult[ExecutedComputedAccumulation](status: ComputedExecutionError.None,
    completed: ExecutedComputedAccumulation(data: ComputedExecutionData(source: source,
        execution: executed.value)))
