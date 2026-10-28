# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded current accumulation driving and genuine terminal-sequence ownership.
## Completion covers recursive accumulation entries, not final statistics/time/history or whole-block publication.
import ../chain/parameters as chain_parameters
import ../codec/bounded as codec_bounded
import ./accumulation_current_round as state_accumulation_current_round
import ./accumulation_current_sequence as state_accumulation_current_sequence
import ./accumulation_round as state_accumulation_round
import ./store as state_store

type
  CurrentSequenceDriverLimits* = object ## Initial work, recursive planning and bounded entry execution keep independent caller policies.
    initial*: CurrentAccumulationRoundLimits
    planning*: CurrentContinuationLimits
    execution*: CurrentContinuationExecutionLimits
  CurrentSequenceDriverError* {.pure.} = enum ## Failed/default alternatives expose no earlier successful entry or partial selected state.
    Uninitialized, None, InvalidSequence, InvalidPlan, Incomplete, LimitExceeded,
    InitialFailure, PlanningFailure, ExecutionFailure
  CurrentCompletionData = ref object # The terminal plan retains exact admitted history and proves no further affordable/transfer entry dispatches.
    terminal: PreparedCurrentContinuation
  CompletedCurrentAccumulationSequence* = object ## Only terminal-plan verification constructs completion; mutable copied observations grant no authority.
    data: nil CurrentCompletionData
  CurrentSequenceDriverResult*[T] = object ## Only success exposes a complete owner; failure retains its genuinely refused parent.
    case status: CurrentSequenceDriverError
    of None:
      completed: T
    of InitialFailure:
      initialReason: CurrentAccumulationRoundResult[PreparedCurrentAccumulationRound]
    of PlanningFailure:
      planningReason: CurrentSequenceResult[PreparedCurrentContinuation]
    of ExecutionFailure:
      executionReason: CurrentSequenceResult[CurrentAccumulationSequence]
    else:
      discard # Handle/policy/terminal refusals carry no partial state or successful source prefix.

func error*[T](outcome: CurrentSequenceDriverResult[T]): CurrentSequenceDriverError =
  ## Inspect only the selected alternative without permitting retagging.
  outcome.status
func value*[T](outcome: CurrentSequenceDriverResult[T]): T {.inline,
    requires: outcome.status == CurrentSequenceDriverError.None.} =
  ## Extract complete selected ownership only after success under checked optimized contracts.
  outcome.completed
func initialFailure*[T](outcome: CurrentSequenceDriverResult[T]): CurrentAccumulationRoundResult[
    PreparedCurrentAccumulationRound] {.inline,

requires: outcome.status == CurrentSequenceDriverError.InitialFailure.} =
  ## Retain only the actual failed initial orchestration, never a successful earlier round.
  outcome.initialReason
func planningFailure*[T](outcome: CurrentSequenceDriverResult[T]): CurrentSequenceResult[
    PreparedCurrentContinuation] {.inline,

requires: outcome.status == CurrentSequenceDriverError.PlanningFailure.} =
  ## Preserve the actual bounded suffix/input classification refusal.
  outcome.planningReason
func executionFailure*[T](outcome: CurrentSequenceDriverResult[T]): CurrentSequenceResult[
    CurrentAccumulationSequence] {.inline,

requires: outcome.status == CurrentSequenceDriverError.ExecutionFailure.} =
  ## Preserve the actual refused later entry and its original nested reason without a successful prefix.
  outcome.executionReason
proc finishCurrentAccumulationSequence*(terminal: PreparedCurrentContinuation): CurrentSequenceDriverResult[
    CompletedCurrentAccumulationSequence] =
  ## Require genuine initialized planning and no further dispatch; copied metadata cannot invent protocol termination.
  let info = terminal.currentContinuationInfo
  if info.error != CurrentSequenceError.None:
    return CurrentSequenceDriverResult[CompletedCurrentAccumulationSequence](
        status: CurrentSequenceDriverError.InvalidPlan)
  if info.value.dispatch:
    return CurrentSequenceDriverResult[CompletedCurrentAccumulationSequence](
        status: CurrentSequenceDriverError.Incomplete) # An affordable report or pending transfer still needs actual execution.
  CurrentSequenceDriverResult[CompletedCurrentAccumulationSequence](
    status: CurrentSequenceDriverError.None,
    completed: CompletedCurrentAccumulationSequence(data: CurrentCompletionData(
        terminal: terminal)))
proc runCurrentAccumulationSequence*(source: CurrentAccumulationSequence,
    planning: CurrentContinuationLimits, execution: CurrentContinuationExecutionLimits):
    CurrentSequenceDriverResult[CompletedCurrentAccumulationSequence] =
  ## Drive only genuine current history; each successful dispatch appends one fact, and its explicit entry cap bounds the loop.
  if source.currentSequenceInfo.error != CurrentSequenceError.None:
    return CurrentSequenceDriverResult[CompletedCurrentAccumulationSequence](
        status: CurrentSequenceDriverError.InvalidSequence)
  var current = source
  while true:
    let planned = planCurrentAccumulationContinuation(current, planning)
    if planned.error != CurrentSequenceError.None:
      return CurrentSequenceDriverResult[CompletedCurrentAccumulationSequence](
        status: CurrentSequenceDriverError.PlanningFailure,
        planningReason: planned) # All earlier private successes release on refusal.
    if not planned.value.currentContinuationInfo.value.dispatch:
      return finishCurrentAccumulationSequence(planned.value) # Terminal proof requires no extra guest/history slot, including at the exact entry ceiling.
    let executed = runCurrentAccumulationContinuation(planned.value, execution)
    if executed.error != CurrentSequenceError.None:
      return CurrentSequenceDriverResult[CompletedCurrentAccumulationSequence](
        status: CurrentSequenceDriverError.ExecutionFailure,
        executionReason: executed) # Only the genuinely failed parent survives; earlier selected states remain private.
    current = executed.value # A fresh flat vector has strictly one more fact; the pre-execution cap makes further dispatch finite.
proc runCurrentBlockAccumulationSequence*(round: BlockAccumulationRound, parameters: Parameters,
    limits: CurrentSequenceDriverLimits): CurrentSequenceDriverResult[
        CompletedCurrentAccumulationSequence] =
  ## Execute the initial cohort once and drive all current continuations without caller-supplied replacement frame, gas or prefix data.
  if uint64(limits.execution.entries) == 0:
    return CurrentSequenceDriverResult[CompletedCurrentAccumulationSequence](
        status: CurrentSequenceDriverError.LimitExceeded) # A retained initial fact needs capacity before any guest work.
  let initial = runCurrentBlockAccumulationRound(round, parameters, limits.initial)
  if initial.error != CurrentAccumulationRoundError.None:
    return CurrentSequenceDriverResult[CompletedCurrentAccumulationSequence](
      status: CurrentSequenceDriverError.InitialFailure,
      initialReason: initial) # No synthetic initial completion hides source/setup/runtime refusal.
  let source = startCurrentAccumulationSequence(initial.value)
  if source.error != CurrentSequenceError.None:
    return CurrentSequenceDriverResult[CompletedCurrentAccumulationSequence](
        status: CurrentSequenceDriverError.InvalidSequence) # Genuine initial orchestration must retain an initialized source graph.
  runCurrentAccumulationSequence(source.value, limits.planning, limits.execution)
proc completedSequencePlan*(completed: CompletedCurrentAccumulationSequence): CurrentSequenceDriverResult[
    PreparedCurrentContinuation] =
  ## Retain the exact terminal proof; default completion cannot claim queue exhaustion or unaffordability.
  let data = completed.data
  if data == nil:
    return CurrentSequenceDriverResult[PreparedCurrentContinuation](
        status: CurrentSequenceDriverError.Uninitialized)
  CurrentSequenceDriverResult[PreparedCurrentContinuation](status: CurrentSequenceDriverError.None,
      completed: data.terminal)
proc completedSequenceSource*(completed: CompletedCurrentAccumulationSequence): CurrentSequenceDriverResult[
    CurrentAccumulationSequence] =
  ## Retain complete flat history through its genuine terminal owner, without mutable row exposure.
  let data = completed.data
  if data == nil:
    return CurrentSequenceDriverResult[CurrentAccumulationSequence](
        status: CurrentSequenceDriverError.Uninitialized)
  CurrentSequenceDriverResult[CurrentAccumulationSequence](status: CurrentSequenceDriverError.None,
    completed: data.terminal.currentContinuationSource.value)
proc completedSequenceInfo*(completed: CompletedCurrentAccumulationSequence): CurrentSequenceDriverResult[
    CurrentSequenceInfo] =
  ## Copy completed progress/budget while keeping final block-statistics/time/publication claims separate.
  let data = completed.data
  if data == nil:
    return CurrentSequenceDriverResult[CurrentSequenceInfo](
        status: CurrentSequenceDriverError.Uninitialized)
  CurrentSequenceDriverResult[CurrentSequenceInfo](status: CurrentSequenceDriverError.None,
    completed: data.terminal.currentContinuationSource.value.currentSequenceInfo.value)
proc completedSequenceState*(completed: CompletedCurrentAccumulationSequence): CurrentSequenceDriverResult[
    StateStoreSnapshot] =
  ## Retain selected recursive accumulation state only; this does not certify final whole-block serialization/publication.
  let data = completed.data
  if data == nil:
    return CurrentSequenceDriverResult[StateStoreSnapshot](
        status: CurrentSequenceDriverError.Uninitialized)
  CurrentSequenceDriverResult[StateStoreSnapshot](status: CurrentSequenceDriverError.None,
    completed: data.terminal.currentContinuationState.value)
