# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Drive genuine completed initial accumulation through bounded report-only rounds to an actual stopped certificate.
## Exposes explicit per-entry/depth policy and guarded terminal alternatives/reasons; never publishes caller state.

import ../chain/parameters
import ./[accumulation_execution, accumulation_continuation, accumulation_continuation_inputs,
  accumulation_continuation_execution, accumulation_reentry, accumulation_runner,
  accumulation_later_runner]

type
  AccumulationDriverLimits* = object ## One continuation plus depth-bounded reentries, with independent local ceilings per entry.
    preparation*: AccumulationReentryConfig ## Reuse selection and materialization policies for every newly prepared range.
    execution*: AccumulationRunnerLimits ## Real guest, context, effect and complete-batch ceilings per entry.
    depth*: AccumulationReentryDepthLimit ## Maximum retained reentry ordinal, including the stopped reentry; zero permits only idle continuation.
  StoppedAccumulationKind* {.pure.} = enum ## Default is not stopped; genuine alternatives identify which existing completion is retained.
    Uninitialized, Continuation, Reentry
  StoppedAccumulation* = object ## Only this driver constructs an immutable stopped owner; no successful live prefix can escape.
    case selection: StoppedAccumulationKind
    of Continuation:
      continuation: CompletedAccumulationContinuation
    of Reentry:
      reentry: CompletedAccumulationReentry
    else:
      discard # No default completion payload exists.
  AccumulationDriverError* {.pure.} = enum ## Failures expose no earlier completed prefix or partially applied candidate.
    Uninitialized, None, InvalidSource, DepthExceeded, SelectionFailure, InputFailure,
    ContinuationFailure, ReentryPreparationFailure, ReentryExecutionFailure
  AccumulationDriverResult* = object ## Private result alternatives retain only genuinely failed parents and their nested reasons.
    case status: AccumulationDriverError
    of None:
      completed: StoppedAccumulation
    of SelectionFailure:
      selectionReason: AccumulationContinuationResult[PreparedAccumulationContinuation]
    of InputFailure:
      inputReason: AccumulationContinuationInputResult[PreparedAccumulationContinuationInputs]
    of ContinuationFailure:
      continuationReason: AccumulationLaterRunnerResult[CompletedAccumulationContinuation]
    of ReentryPreparationFailure:
      preparationReason: AccumulationReentryResult[PreparedAccumulationReentry]
    of ReentryExecutionFailure:
      executionReason: AccumulationLaterRunnerResult[CompletedAccumulationReentry]
    else:
      discard # Defaults, invalid source and depth refusals carry reasons alone.

func stoppedKind*(source: StoppedAccumulation): StoppedAccumulationKind =
  ## Inspect initialized terminal provenance without permitting retagging.
  source.selection
func stoppedContinuation*(source: StoppedAccumulation): CompletedAccumulationContinuation {.inline,
    requires: source.selection == StoppedAccumulationKind.Continuation.} =
  ## Retain only a genuinely stopped first continuation, compatible with existing finalization.
  source.continuation
func stoppedReentry*(source: StoppedAccumulation): CompletedAccumulationReentry {.inline,
    requires: source.selection == StoppedAccumulationKind.Reentry.} =
  ## Retain only a genuinely stopped reentry and its acyclic completed history.
  source.reentry
func error*(outcome: AccumulationDriverResult): AccumulationDriverError =
  ## Inspect the selected reason without exposing writable variant storage.
  outcome.status
func value*(outcome: AccumulationDriverResult): StoppedAccumulation {.inline,
    requires: outcome.status == AccumulationDriverError.None.} =
  ## Extract only selected complete success; depth exhaustion never authorizes this accessor.
  outcome.completed
func selectionFailure*(outcome: AccumulationDriverResult):
    AccumulationContinuationResult[PreparedAccumulationContinuation] {.inline,
    requires: outcome.status == AccumulationDriverError.SelectionFailure.} =
  ## Inspect the actual failed prefix selection, including the outgoing-transfer gate.
  outcome.selectionReason
func inputFailure*(outcome: AccumulationDriverResult):
    AccumulationContinuationInputResult[PreparedAccumulationContinuationInputs] {.inline,
    requires: outcome.status == AccumulationDriverError.InputFailure.} =
  ## Inspect actual selected-range/input/private batch refusal with its existing guarded children.
  outcome.inputReason
func continuationFailure*(outcome: AccumulationDriverResult):
    AccumulationLaterRunnerResult[CompletedAccumulationContinuation] {.inline,
    requires: outcome.status == AccumulationDriverError.ContinuationFailure.} =
  ## Retain the failed continuation runner result, including engine and batch/provision reasons.
  outcome.continuationReason
func reentryPreparationFailure*(outcome: AccumulationDriverResult):
    AccumulationReentryResult[PreparedAccumulationReentry] {.inline,
    requires: outcome.status == AccumulationDriverError.ReentryPreparationFailure.} =
  ## Retain the actual refused next-entry preparation without an earlier successful state.
  outcome.preparationReason
func reentryExecutionFailure*(outcome: AccumulationDriverResult):
    AccumulationLaterRunnerResult[CompletedAccumulationReentry] {.inline,
    requires: outcome.status == AccumulationDriverError.ReentryExecutionFailure.} =
  ## Retain the actual refused reentry execution with all selected nested reasons intact.
  outcome.executionReason

proc driveAccumulation*(source: CompletedBlockAccumulation, parameters: Parameters,
    limits: AccumulationDriverLimits): AccumulationDriverResult =
  ## Start at genuine initial completion, never replay initial guests, and return only a certified n=0 history.
  ## Each next preparation applies only its immediate completed batch on a private full-state fork.
  if source.executionInfo.error != AccumulationExecutionError.None:
    return AccumulationDriverResult(status: AccumulationDriverError.InvalidSource) # Defaults cannot authorize selection.
  let selected = planAccumulationContinuation(source, limits.preparation.selection)
  if selected.error != AccumulationContinuationError.None:
    return AccumulationDriverResult(status: AccumulationDriverError.SelectionFailure,
      selectionReason: selected) # Failed parents alone are retained; no live prefix escapes.
  if selected.value.continuationInfo.value.dispatch and uint64(limits.depth) == 0:
    return AccumulationDriverResult(status: AccumulationDriverError.DepthExceeded) # A dispatched continuation needs at least a stopped first reentry.
  let inputs = prepareAccumulationContinuationInputs(selected.value,
    AccumulationContinuationInputConfig(operands: limits.preparation.operands,
      inputs: limits.preparation.inputs))
  if inputs.error != AccumulationContinuationInputError.None:
    return AccumulationDriverResult(status: AccumulationDriverError.InputFailure,
      inputReason: inputs) # No partially applied initial batch or selected inputs survive failure.
  let later = runAccumulationContinuation(inputs.value, parameters, limits.execution)
  if later.error != AccumulationLaterRunnerError.None:
    return AccumulationDriverResult(status: AccumulationDriverError.ContinuationFailure,
      continuationReason: later) # Preserve exact local engine, context and completion causes.
  if not later.value.executionInfo.value.round.dispatch:
    return AccumulationDriverResult(status: AccumulationDriverError.None,
      completed: StoppedAccumulation(selection: StoppedAccumulationKind.Continuation,
        continuation: later.value)) # The actual stopped completion retains its already-applied initial state.
  let first = prepareAccumulationReentry(later.value, limits.preparation)
  if first.error != AccumulationReentryError.None:
    return AccumulationDriverResult(status: AccumulationDriverError.ReentryPreparationFailure,
      preparationReason: first) # Transfer/selection/input/application gates remain authoritative.
  var entry = first.value
  while true:
    # Each successful live iteration advances a checked depth below the explicit cap; stopped entries return immediately.
    let completed = runAccumulationReentry(entry, parameters, limits.execution)
    if completed.error != AccumulationLaterRunnerError.None:
      return AccumulationDriverResult(status: AccumulationDriverError.ReentryExecutionFailure,
        executionReason: completed) # Release all earlier successful rounds on late refusal.
    let facts = completed.value.executionInfo.value.round
    if not facts.dispatch:
      return AccumulationDriverResult(status: AccumulationDriverError.None,
        completed: StoppedAccumulation(selection: StoppedAccumulationKind.Reentry,
          reentry: completed.value)) # Only n=0 authorizes a stopped result, even if an earlier suffix was exhausted.
    if uint64(facts.depth) >= uint64(limits.depth):
      return AccumulationDriverResult(status: AccumulationDriverError.DepthExceeded) # Refuse before next preparation/guest work or depth increment.
    let next = prepareAccumulationReentry(completed.value, limits.preparation, limits.depth)
    if next.error != AccumulationReentryError.None:
      return AccumulationDriverResult(status: AccumulationDriverError.ReentryPreparationFailure,
        preparationReason: next) # Preserve nested refusal without publishing partial successful history.
    entry = next.value # Existing checked preparation increments depth and retains only immutable backward history.
