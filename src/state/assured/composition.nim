# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Stop, finalize and compose actual assured execution without replaying initial guests or publishing a partial successor.

import ../../chain/parameters
import ./execution as assured_execution
import ../accumulation/[driver as accumulation_driver, finalization as accumulation_finalization,
    outputs as accumulation_outputs, completion as accumulation_completion,
    consensus as accumulation_consensus]

type
  AssuredCompositionConfig* = object ## Independent maintained-phase ceilings never replace retained parameter or block authority.
    driver*: AccumulationDriverLimits
    outputs*: AccumulationOutputHistoryLimits
    composition*: AccumulationCompositionLimits
  AssuredCompositionError* {.pure.} = enum ## Only selected genuine maintained refusals carry their complete original result.
    Uninitialized, None, InvalidSource, DriverFailure, FinalizationFailure, CompositionFailure
  AssuredCompositionData = ref object ## Immutable acyclic storage keeps original actual execution and all successful terminal/composition certificates.
    source: ExecutedAssuredAccumulation
    stopped: StoppedAccumulation
    final: PreparedFinalAccumulation
    plan: PreparedAccumulationConsensus
  ComposedAssuredState* = object ## Preparation is private and does not certify canonical publication or complete chain validation.
    data: nil AssuredCompositionData
  AssuredCompositionResult*[T] = object ## Refusals/defaults expose no earlier successful history or partial composed state.
    case status: AssuredCompositionError
    of None: completed: T
    of DriverFailure: driverReason: AccumulationDriverResult
    of FinalizationFailure: finalizationReason: AccumulationFinalizationResult[PreparedFinalAccumulation]
    of CompositionFailure: compositionReason: AccumulationCompletionResult
    else: discard # Ordinary refusals carry their selected reason alone.

func error*[T](outcome: AssuredCompositionResult[T]): AssuredCompositionError =
  ## Inspect selection without writable discriminator access.
  outcome.status
func value*[T](outcome: AssuredCompositionResult[T]): T {.requires: outcome.status ==
    AssuredCompositionError.None.} =
  ## Guard complete-success extraction under optimized compilation.
  outcome.completed
func driverFailure*[T](outcome: AssuredCompositionResult[
    T]): AccumulationDriverResult {.requires: outcome.status ==
    AssuredCompositionError.DriverFailure.} =
  ## Retain only the real refused driver result and its guarded selected cause.
  outcome.driverReason
func finalizationFailure*[T](outcome: AssuredCompositionResult[T]): AccumulationFinalizationResult[
    PreparedFinalAccumulation] {.requires: outcome.status ==
    AssuredCompositionError.FinalizationFailure.} =
  ## Retain only the actual failed finalizer, including output/store reasons.
  outcome.finalizationReason
func compositionFailure*[T](outcome: AssuredCompositionResult[
    T]): AccumulationCompletionResult {.requires: outcome.status ==
    AssuredCompositionError.CompositionFailure.} =
  ## Retain the actual refused state phase without exposing any earlier successful map.
  outcome.compositionReason
proc assuredCompositionSource*(composed: ComposedAssuredState): AssuredCompositionResult[
    ExecutedAssuredAccumulation] =
  ## Share actual PVM completion and original authenticated assurance/report authority.
  let data = composed.data
  if data == nil: return AssuredCompositionResult[ExecutedAssuredAccumulation](
      status: AssuredCompositionError.Uninitialized)
  AssuredCompositionResult[ExecutedAssuredAccumulation](status: AssuredCompositionError.None,
      completed: data.source)
proc assuredCompositionStopped*(composed: ComposedAssuredState): AssuredCompositionResult[
    StoppedAccumulation] =
  ## Share the genuine stopped history after all source handles retire.
  let data = composed.data
  if data == nil: return AssuredCompositionResult[StoppedAccumulation](
      status: AssuredCompositionError.Uninitialized)
  AssuredCompositionResult[StoppedAccumulation](status: AssuredCompositionError.None,
      completed: data.stopped)
proc assuredCompositionFinal*(composed: ComposedAssuredState): AssuredCompositionResult[
    PreparedFinalAccumulation] =
  ## Share actual execution-side finalization independently of the fully composed state view.
  let data = composed.data
  if data == nil: return AssuredCompositionResult[PreparedFinalAccumulation](
      status: AssuredCompositionError.Uninitialized)
  AssuredCompositionResult[PreparedFinalAccumulation](status: AssuredCompositionError.None,
      completed: data.final)
proc assuredCompositionPlan*(composed: ComposedAssuredState): AssuredCompositionResult[
    PreparedAccumulationConsensus] =
  ## Share only the genuine completed state composition certificate.
  let data = composed.data
  if data == nil: return AssuredCompositionResult[PreparedAccumulationConsensus](
      status: AssuredCompositionError.Uninitialized)
  AssuredCompositionResult[PreparedAccumulationConsensus](status: AssuredCompositionError.None,
      completed: data.plan)
proc assuredCompositionParameters*(composed: ComposedAssuredState): AssuredCompositionResult[Parameters] =
  ## Inspect all original parameters without permitting replacement execution authority.
  let data = composed.data
  if data == nil: return AssuredCompositionResult[Parameters](
      status: AssuredCompositionError.Uninitialized)
  AssuredCompositionResult[Parameters](status: AssuredCompositionError.None,
      completed: data.source.assuredExecutionParameters.value)
proc composeAssuredState*(source: ExecutedAssuredAccumulation,
    config: AssuredCompositionConfig): AssuredCompositionResult[ComposedAssuredState] =
  ## Derive retained parameters, certify actual termination and prepare every state phase once before exposing success.
  let completed = source.assuredExecutionCompleted
  if completed.error != AssuredExecutionError.None:
    return AssuredCompositionResult[ComposedAssuredState](
        status: AssuredCompositionError.InvalidSource) # Defaults never authorize a synthetic empty completion.
  let stopped = driveAccumulation(completed.value, source.assuredExecutionParameters.value, config.driver)
  if stopped.error != AccumulationDriverError.None:
    return AssuredCompositionResult[ComposedAssuredState](
        status: AssuredCompositionError.DriverFailure,
        driverReason: stopped) # No live earlier history escapes a later refusal.
  let finalized = prepareFinalAccumulation(stopped.value, config.outputs)
  if finalized.error != AccumulationFinalizationError.None:
    return AssuredCompositionResult[ComposedAssuredState](
        status: AssuredCompositionError.FinalizationFailure,
        finalizationReason: finalized) # No candidate is exposed before actual terminal finalization succeeds.
  let composed = prepareAccumulationComposition(finalized.value, config.composition)
  if composed.error != AccumulationCompletionError.None:
    return AssuredCompositionResult[ComposedAssuredState](
        status: AssuredCompositionError.CompositionFailure,
        compositionReason: composed) # Successful earlier private state phases retire together on refusal.
  AssuredCompositionResult[ComposedAssuredState](status: AssuredCompositionError.None,
    completed: ComposedAssuredState(data: AssuredCompositionData(source: source,
        stopped: stopped.value, final: finalized.value, plan: composed.value)))
