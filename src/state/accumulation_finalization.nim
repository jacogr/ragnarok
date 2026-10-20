# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Finalize supported report-only accseq on a private full-state fork after a genuine stopped completion.
## Retains terminal provenance, earlier service effects and fresh C(16); whole-block publication remains separate.

import ../codec/[work_digest, state_trie]
import ./[accumulation_driver, accumulation_outputs, accumulation_execution, accumulation_round,
  accumulation_queue, report_admission, block_transition, block_admission, accumulation_operands,
  accumulation_continuation_execution,
  accumulation_continuation_inputs, accumulation_continuation, accumulation_reentry, store]

type
  AccumulationFinalizationInfo* = object ## Copied terminal facts distinguish a stopped budget from an exhausted queue.
    completedPrefix*: AccumulationReportPrefix ## Original reports processed before the certified idle terminal entry.
    pendingReports*: int ## Original suffix left unprocessed; this may be nonzero when its first report cannot fit.
    remainingGas*: Gas ## Recursive budget after actual completed consumption, not declared reservations.
    outputs*: AccumulationOutputsInfo ## Completed history work and the unique pair/log extent retained in C(16).
  AccumulationFinalizationError* {.pure.} = enum ## Refusals carry only reasons, never terminal state or a partial output projection.
    Uninitialized, ## Default result or candidate owner.
    None,          ## Selected complete success permits extraction.
    InvalidSource, ## No genuine completed continuation or reentry was supplied.
    NotStopped,    ## The completed source dispatched services; another entry must establish n=0 first.
    OutputFailure, ## Inspect the selected output preparation reason.
    StateFailure   ## Inspect the selected private store/publication reason.
  # Immutable acyclic ownership retains authentic source history through the output projection.
  FinalAccumulationData = ref object
    outputs: PreparedAccumulationOutputs
    state: StateStoreSnapshot
    info: AccumulationFinalizationInfo
  PreparedFinalAccumulation* = object ## Only a stopped completion can authorize this complete-map report-only candidate.
    data: nil FinalAccumulationData
  AccumulationFinalizationResult*[T] = object ## Failed/default alternatives contain no application payload or prior successful candidate.
    case status: AccumulationFinalizationError
    of None:
      completed: T # Selected success is the only payload-bearing alternative.
    of OutputFailure:
      outputReason: AccumulationOutputsError
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard      # Default, invalid and live-source alternatives carry reasons alone.

func error*[T](outcome: AccumulationFinalizationResult[T]): AccumulationFinalizationError =
  ## Read the selected reason without permitting retagging.
  outcome.status

func value*[T](outcome: AccumulationFinalizationResult[T]): T {.inline,
    requires: outcome.status == AccumulationFinalizationError.None.} =
  ## Extract only complete success under checked optimized contracts.
  outcome.completed

func outputError*[T](outcome: AccumulationFinalizationResult[T]): AccumulationOutputsError {.inline,
    requires: outcome.status == AccumulationFinalizationError.OutputFailure.} =
  ## Inspect only a genuine output collection refusal.
  outcome.outputReason

func stateError*[T](outcome: AccumulationFinalizationResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationFinalizationError.StateFailure.} =
  ## Inspect only a genuine private state-publication refusal.
  outcome.stateReason

proc finalAccumulationInfo*(plan: PreparedFinalAccumulation):
    AccumulationFinalizationResult[AccumulationFinalizationInfo] =
  ## Copy terminal progress and output counts without exposing mutable retained storage.
  let data = plan.data
  if data == nil:
    return AccumulationFinalizationResult[AccumulationFinalizationInfo](
      status: AccumulationFinalizationError.Uninitialized) # Defaults do not represent an empty terminal sequence.
  AccumulationFinalizationResult[AccumulationFinalizationInfo](
    status: AccumulationFinalizationError.None, completed: data.info)

proc finalAccumulationOutputs*(plan: PreparedFinalAccumulation):
    AccumulationFinalizationResult[PreparedAccumulationOutputs] =
  ## Retain exact terminal history and its selected pair union for copied queries or explicit root derivation.
  let data = plan.data
  if data == nil:
    return AccumulationFinalizationResult[PreparedAccumulationOutputs](
      status: AccumulationFinalizationError.Uninitialized) # No fabricated output log or source chain.
  AccumulationFinalizationResult[PreparedAccumulationOutputs](
    status: AccumulationFinalizationError.None, completed: data.outputs)

proc finalAccumulationState*(plan: PreparedFinalAccumulation):
    AccumulationFinalizationResult[StateStoreSnapshot] =
  ## Retain the complete private candidate after C(16), preserving all prior service state and store ceilings.
  let data = plan.data
  if data == nil:
    return AccumulationFinalizationResult[StateStoreSnapshot](
      status: AccumulationFinalizationError.Uninitialized) # A default handle is never a complete empty map.
  AccumulationFinalizationResult[StateStoreSnapshot](
    status: AccumulationFinalizationError.None, completed: data.state)

proc finalAccumulationQueue*(plan: PreparedFinalAccumulation):
    AccumulationFinalizationResult[BlockAccumulationQueue] =
  ## Retain the exact initial queue owner behind this finalized successor; defaults expose no fabricated provenance.
  let data = plan.data
  if data == nil:
    return AccumulationFinalizationResult[BlockAccumulationQueue](
        status: AccumulationFinalizationError.Uninitialized)
  AccumulationFinalizationResult[BlockAccumulationQueue](status: AccumulationFinalizationError.None,
    completed: data.outputs.outputsSource.value.executionRound.value.roundBlockQueue.value)

proc finalAccumulationAdmission*(plan: PreparedFinalAccumulation):
    AccumulationFinalizationResult[AdmittedReports] =
  ## Retain authenticated block/profile authority from the successor's own execution graph, never a caller replacement.
  let queue = plan.finalAccumulationQueue
  if queue.error != AccumulationFinalizationError.None:
    return AccumulationFinalizationResult[AdmittedReports](
        status: queue.error) # No default admission can authorize state composition.
  AccumulationFinalizationResult[AdmittedReports](status: AccumulationFinalizationError.None,
    completed: queue.value.accumulationAdmission.value)

proc finalAccumulationParent*(plan: PreparedFinalAccumulation):
    AccumulationFinalizationResult[StateStoreSnapshot] =
  ## Retain the exact original admitted complete-map parent for final publication's physical owner check.
  let admission = plan.finalAccumulationAdmission
  if admission.error != AccumulationFinalizationError.None:
    return AccumulationFinalizationResult[StateStoreSnapshot](
        status: admission.error) # Equal roots or detached maps never substitute a source.
  AccumulationFinalizationResult[StateStoreSnapshot](status: AccumulationFinalizationError.None,
    completed: admission.value.reportBlockStage.value.value.admitted.admittedState)

# Only genuine stopped sources call this helper with their exact prior and bounded collected outputs.
proc finalize(prior: StateStoreSnapshot, collected: AccumulationOutputsResult[
    PreparedAccumulationOutputs], processed: AccumulationReportPrefix, pending: int,
        remaining: Gas):
    AccumulationFinalizationResult[PreparedFinalAccumulation] =
  if collected.error != AccumulationOutputsError.None:
    return AccumulationFinalizationResult[PreparedFinalAccumulation](
      status: AccumulationFinalizationError.OutputFailure,
      outputReason: collected.error) # Drop any private scratch; output refusals carry no successful owner.
  let outputs = collected.value
  let entry = outputs.outputsEntry.value # Preparation already proved the retained codec extents.
  var working = forkStateStore(prior).value # Authentic terminal preparation guarantees a complete initialized map.
  let applied = working.apply([StateWrite(key: entry.key, kind: StateWriteKind.Put,
    value: entry.value)])
  if applied.error != StateStoreError.None:
    return AccumulationFinalizationResult[PreparedFinalAccumulation](
      status: AccumulationFinalizationError.StateFailure,
      stateReason: applied.error) # No changed source head or partly successful candidate survives.
  AccumulationFinalizationResult[PreparedFinalAccumulation](
    status: AccumulationFinalizationError.None,
    completed: PreparedFinalAccumulation(data: FinalAccumulationData(outputs: outputs,
      state: applied.value, info: AccumulationFinalizationInfo(completedPrefix: processed,
        pendingReports: pending, remainingGas: remaining, outputs: outputs.outputsInfo.value))))

proc prepareFinalAccumulation*(source: CompletedAccumulationContinuation,
    limits: AccumulationOutputHistoryLimits): AccumulationFinalizationResult[
        PreparedFinalAccumulation] =
  ## Finalize only a stopped first continuation; its prior already includes the initial batch exactly once.
  let info = source.executionInfo
  if info.error != AccumulationContinuationExecutionError.None:
    return AccumulationFinalizationResult[PreparedFinalAccumulation](
      status: AccumulationFinalizationError.InvalidSource) # Defaults cannot authorize terminal state or output work.
  let round = info.value.round
  if round.dispatch:
    return AccumulationFinalizationResult[PreparedFinalAccumulation](
      status: AccumulationFinalizationError.NotStopped) # Actual execution completion alone does not establish accseq n=0.
  finalize(source.executionContinuation.value.continuationState.value,
    prepareAccumulationOutputs(source, limits), round.completedPrefix, round.pendingReports, round.budget)

proc prepareFinalAccumulation*(source: CompletedAccumulationReentry,
    limits: AccumulationOutputHistoryLimits): AccumulationFinalizationResult[
        PreparedFinalAccumulation] =
  ## Finalize only a stopped repeated entry; retain its actual fully applied prior without replaying history.
  let info = source.executionInfo
  if info.error != AccumulationReentryExecutionError.None:
    return AccumulationFinalizationResult[PreparedFinalAccumulation](
      status: AccumulationFinalizationError.InvalidSource) # Default completions are not empty terminal histories.
  let round = info.value.round
  if round.dispatch:
    return AccumulationFinalizationResult[PreparedFinalAccumulation](
      status: AccumulationFinalizationError.NotStopped) # Even an exhausted suffix needs a certified stopped entry.
  finalize(source.executionReentry.value.reentryState.value,
    prepareAccumulationOutputs(source, limits), round.completedPrefix, round.pendingReports, round.budget)


proc prepareFinalAccumulation*(source: StoppedAccumulation,
    limits: AccumulationOutputHistoryLimits): AccumulationFinalizationResult[
        PreparedFinalAccumulation] =
  ## Execution finalizes its genuine stopped variant once; state composition need not inspect driver alternatives.
  case source.stoppedKind
  of StoppedAccumulationKind.Continuation:
    prepareFinalAccumulation(source.stoppedContinuation,
        limits) # Preserve actual stopped first-continuation provenance.
  of StoppedAccumulationKind.Reentry:
    prepareFinalAccumulation(source.stoppedReentry,
        limits) # Preserve the retained bounded repeated execution history.
  else:
    AccumulationFinalizationResult[PreparedFinalAccumulation](
        status: AccumulationFinalizationError.InvalidSource) # Default cannot certify an empty stopped history.
