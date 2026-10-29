# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Drive original-source computed execution to a genuine stopped history and finalize its private accumulation branch.

import ./[execution as computed_execution, round as computed_round]
import ../accumulation/[execution as accumulation_execution, driver as accumulation_driver,
    finalization as accumulation_finalization, outputs as accumulation_outputs]

type
  ComputedFinalizationConfig* = object ## Independent recursive execution and complete output-history ceilings.
    driver*: AccumulationDriverLimits
    outputs*: AccumulationOutputHistoryLimits
  ComputedFinalizationError* {.pure.} = enum ## Selected child failures preserve their complete precise refusal without partial state.
    Uninitialized, None, InvalidSource, DriverFailure, FinalizationFailure
  ComputedFinalizationData = ref object ## Immutable acyclic provenance retains original computed execution and actual stopped/final certificates.
    source: ExecutedComputedAccumulation
    stopped: StoppedAccumulation
    final: PreparedFinalAccumulation
  FinalizedComputedAccumulation* = object ## The private accumulation branch still requires source-bound state composition with pending reports.
    data: nil ComputedFinalizationData
  ComputedFinalizationResult*[T] = object ## Only complete selected success carries a usable finalized owner.
    case status: ComputedFinalizationError
    of None:
      completed: T
    of DriverFailure:
      driverReason: AccumulationDriverResult
    of FinalizationFailure:
      finalizationReason: AccumulationFinalizationResult[PreparedFinalAccumulation]
    else:
      discard # Defaults and ordinary refusals contain no successful history prefix.

func error*[T](outcome: ComputedFinalizationResult[T]): ComputedFinalizationError =
  ## Inspect reason without writable discriminator access.
  outcome.status
func value*[T](outcome: ComputedFinalizationResult[T]): T
    {.requires: outcome.status == ComputedFinalizationError.None.} =
  ## Guard complete-success extraction under optimized compilation.
  outcome.completed
func driverFailure*[T](outcome: ComputedFinalizationResult[T]): AccumulationDriverResult
    {.requires: outcome.status == ComputedFinalizationError.DriverFailure.} =
  ## Retain only an actual refused driver result and its guarded nested reason.
  outcome.driverReason
func finalizationFailure*[T](outcome: ComputedFinalizationResult[
    T]): AccumulationFinalizationResult[PreparedFinalAccumulation]
    {.requires: outcome.status == ComputedFinalizationError.FinalizationFailure.} =
  ## Retain only an actual refused finalizer result and its guarded output/store cause.
  outcome.finalizationReason
proc computedFinalizationSource*(finalized: FinalizedComputedAccumulation): ComputedFinalizationResult[
    ExecutedComputedAccumulation] =
  ## Share exact original computations, pending guarantees, actual paid execution and Parameters.
  let data = finalized.data
  if data == nil: return ComputedFinalizationResult[ExecutedComputedAccumulation](
      status: ComputedFinalizationError.Uninitialized)
  ComputedFinalizationResult[ExecutedComputedAccumulation](status: ComputedFinalizationError.None,
      completed: data.source)
proc computedFinalizationStopped*(finalized: FinalizedComputedAccumulation): ComputedFinalizationResult[
    StoppedAccumulation] =
  ## Share only the genuine stopped variant selected by the maintained driver.
  let data = finalized.data
  if data == nil: return ComputedFinalizationResult[StoppedAccumulation](
      status: ComputedFinalizationError.Uninitialized)
  ComputedFinalizationResult[StoppedAccumulation](status: ComputedFinalizationError.None,
      completed: data.stopped)
proc computedFinalizationPlan*(finalized: FinalizedComputedAccumulation): ComputedFinalizationResult[
    PreparedFinalAccumulation] =
  ## Share the actual private accumulation successor, without claiming whole-block publication.
  let data = finalized.data
  if data == nil: return ComputedFinalizationResult[PreparedFinalAccumulation](
      status: ComputedFinalizationError.Uninitialized)
  ComputedFinalizationResult[PreparedFinalAccumulation](status: ComputedFinalizationError.None,
      completed: data.final)
proc finalizeComputedAccumulation*(source: ExecutedComputedAccumulation,
    config: ComputedFinalizationConfig): ComputedFinalizationResult[FinalizedComputedAccumulation] =
  ## Derive original parameter authority, certify n=0 through the real driver and finalize once without replaying initial guests.
  let completed = source.computedExecutionCompleted
  if completed.error != ComputedExecutionError.None:
    return ComputedFinalizationResult[FinalizedComputedAccumulation](
        status: ComputedFinalizationError.InvalidSource)
  let parameters = source.computedExecutionSource.value.computedRoundParameters.value
  let stopped = driveAccumulation(completed.value, parameters, config.driver)
  if stopped.error != AccumulationDriverError.None:
    return ComputedFinalizationResult[FinalizedComputedAccumulation](
      status: ComputedFinalizationError.DriverFailure,
      driverReason: stopped) # No live successful prefix escapes a later recursive refusal.
  let finalized = prepareFinalAccumulation(stopped.value, config.outputs)
  if finalized.error != AccumulationFinalizationError.None:
    return ComputedFinalizationResult[FinalizedComputedAccumulation](
      status: ComputedFinalizationError.FinalizationFailure,
      finalizationReason: finalized) # Failed output/root work retains no candidate map.
  ComputedFinalizationResult[FinalizedComputedAccumulation](status: ComputedFinalizationError.None,
    completed: FinalizedComputedAccumulation(data: ComputedFinalizationData(source: source,
      stopped: stopped.value, final: finalized.value)))
