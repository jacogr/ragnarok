# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compose actual finalized computed execution with its authenticated report/block state through maintained phases.

import ./[computed_finalization, accumulation_completion, accumulation_consensus]

type
  ComputedCompositionError* {.pure.} = enum ## Only selected composition refusal carries its complete precise failed phase.
    Uninitialized, None, InvalidSource, CompositionFailure
  ComputedCompositionData = ref object ## Immutable acyclic ownership retains original computed work and the fully composed state certificate.
    source: FinalizedComputedAccumulation
    plan: PreparedAccumulationConsensus
  ComposedComputedState* = object ## Preparation is not canonical publication or complete block/finality validation.
    data: nil ComputedCompositionData
  ComputedCompositionResult*[T] = object ## Defaults/refusals expose no earlier successful state prefix.
    case status: ComputedCompositionError
    of None:
      completed: T
    of CompositionFailure:
      compositionReason: AccumulationCompletionResult
    else:
      discard # Ordinary refusals carry selected reasons alone.

func error*[T](outcome: ComputedCompositionResult[T]): ComputedCompositionError =
  ## Inspect selection without writable discriminator access.
  outcome.status
func value*[T](outcome: ComputedCompositionResult[T]): T
    {.requires: outcome.status == ComputedCompositionError.None.} =
  ## Guard complete-success extraction under optimized compilation.
  outcome.completed
func compositionFailure*[T](outcome: ComputedCompositionResult[T]): AccumulationCompletionResult
    {.requires: outcome.status == ComputedCompositionError.CompositionFailure.} =
  ## Retain the actual failed maintained phase and its guarded nested cause.
  outcome.compositionReason
proc computedCompositionSource*(composed: ComposedComputedState): ComputedCompositionResult[
    FinalizedComputedAccumulation] =
  ## Share original computation, pending-report and actual stopped-execution authority.
  let data = composed.data
  if data == nil: return ComputedCompositionResult[FinalizedComputedAccumulation](
      status: ComputedCompositionError.Uninitialized)
  ComputedCompositionResult[FinalizedComputedAccumulation](status: ComputedCompositionError.None,
      completed: data.source)
proc computedCompositionPlan*(composed: ComposedComputedState): ComputedCompositionResult[
    PreparedAccumulationConsensus] =
  ## Share only the real fully composed state certificate, never a caller replacement map.
  let data = composed.data
  if data == nil: return ComputedCompositionResult[PreparedAccumulationConsensus](
      status: ComputedCompositionError.Uninitialized)
  ComputedCompositionResult[PreparedAccumulationConsensus](status: ComputedCompositionError.None,
      completed: data.plan)
proc composeComputedState*(source: FinalizedComputedAccumulation,
    limits: AccumulationCompositionLimits): ComputedCompositionResult[ComposedComputedState] =
  ## Compose all maintained phases once from exact finalization provenance, without replaying guests or publishing partial state.
  let selected = source.computedFinalizationPlan
  if selected.error != ComputedFinalizationError.None:
    return ComputedCompositionResult[ComposedComputedState](
        status: ComputedCompositionError.InvalidSource)
  let composed = prepareAccumulationComposition(selected.value, limits)
  if composed.error != AccumulationCompletionError.None:
    return ComputedCompositionResult[ComposedComputedState](
      status: ComputedCompositionError.CompositionFailure,
      compositionReason: composed) # Earlier successful private phase maps are released on every later refusal.
  ComputedCompositionResult[ComposedComputedState](status: ComputedCompositionError.None,
    completed: ComposedComputedState(data: ComputedCompositionData(source: source,
        plan: composed.value)))
