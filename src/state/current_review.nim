# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Review one qualified current successor using only its original full child parameter tuple.
## Targeted account observations remain separate from full semantic validity, installation and root/finality policy.
import std/assertions
import ./[current_state, current_globals, current_profile, economic_profile, account_review_plan, account_review]
type
  CurrentReviewPlan* = object ## Frozen original current serialization and admitted reports retain one immutable source and original parameter rates.
    initialized: bool
    source: CurrentStateSerialization
    plan: StateAccountReviewPlan
  ReviewedCurrentState* = object ## Original serialization and same-inventory account review remain private immutable owners.
    initialized: bool
    source: CurrentStateSerialization
    review: StateAccountReview
  CurrentReviewError* {.pure.} = enum ## No refused preparation/execution grants a completed review or usable prefix.
    Uninitialized, None, InvalidState, ProfileFailure, PreparationFailure, ExecutionFailure, InvalidPlan
  CurrentReviewResult*[T] = object ## Every nested reason is the genuinely failed original stage.
    case status: CurrentReviewError
    of None:
      completed: T
    of ProfileFailure:
      profileReason: EconomicProfileError
    of PreparationFailure:
      preparationReason: AccountReviewPlanResult[StateAccountReviewPlan]
    of ExecutionFailure:
      executionReason: AccountReviewExecutionResult
    else:
      discard                      # Defaults and invalid source handles grant no review.
func error*[T](outcome: CurrentReviewResult[T]): CurrentReviewError =
  ## Observe the immutable selection without granting retagging.
  outcome.status
func value*[T](outcome: CurrentReviewResult[T]): T {.inline, requires: outcome.status ==
    CurrentReviewError.None.} =
  ## Extract only successful complete review/observation owners.
  outcome.completed
func profileError*[T](outcome: CurrentReviewResult[T]): EconomicProfileError {.inline,
    requires: outcome.status == CurrentReviewError.ProfileFailure.} =
  ## Read only an actual original parameter capture refusal.
  outcome.profileReason
func preparationFailure*[T](outcome: CurrentReviewResult[T]): AccountReviewPlanResult[
    StateAccountReviewPlan] {.inline, requires: outcome.status ==
    CurrentReviewError.PreparationFailure.} =
  ## Preserve complete hash-free admission/report failure before content execution.
  outcome.preparationReason
func executionFailure*[T](outcome: CurrentReviewResult[T]): AccountReviewExecutionResult {.inline,
    requires: outcome.status == CurrentReviewError.ExecutionFailure.} =
  ## Preserve only the real targeted predicate/join refusal with no successful prefix.
  outcome.executionReason
proc planCurrentReview*(source: CurrentStateSerialization,
    limits: AccountReviewPlanLimits): CurrentReviewResult[CurrentReviewPlan] =
  ## Admit all original-source report work and rates before content hashing; execution accepts no replacement source or policy.
  let inventory = source.currentStateInventory
  if inventory.error != CurrentStateError.None:
    return CurrentReviewResult[CurrentReviewPlan](status: CurrentReviewError.InvalidState)
  let parameters = source.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedParameters.value
  let profile = captureEconomicProfile(parameters)
  if profile.error != EconomicProfileError.None:
    return CurrentReviewResult[CurrentReviewPlan](status: CurrentReviewError.ProfileFailure,
        profileReason: profile.error)
  let plan = planAccountReview(inventory.value, profile.value, limits)
  if plan.error != AccountReviewPlanError.None:
    return CurrentReviewResult[CurrentReviewPlan](status: CurrentReviewError.PreparationFailure,
        preparationReason: plan) # Complete report admission remains before any content work.
  CurrentReviewResult[CurrentReviewPlan](status: CurrentReviewError.None,
    completed: CurrentReviewPlan(initialized: true, source: source, plan: plan.value))
proc currentReviewPlanInfo*(source: CurrentReviewPlan): CurrentReviewResult[AccountReviewPlanInfo] =
  ## Observe copied admitted work/coverage while keeping the original source and rate owners private.
  if not source.initialized:
    return CurrentReviewResult[AccountReviewPlanInfo](status: CurrentReviewError.InvalidPlan)
  CurrentReviewResult[AccountReviewPlanInfo](status: CurrentReviewError.None,
    completed: source.plan.reviewPlanInfo.value)
proc executeCurrentReview*(source: CurrentReviewPlan): CurrentReviewResult[ReviewedCurrentState] =
  ## Retry original targeted content predicates against exactly the already admitted immutable source.
  if not source.initialized:
    return CurrentReviewResult[ReviewedCurrentState](status: CurrentReviewError.InvalidPlan)
  let review = executeAccountReview(source.plan)
  if review.error != AccountReviewExecutionError.None:
    return CurrentReviewResult[ReviewedCurrentState](status: CurrentReviewError.ExecutionFailure,
      executionReason: review) # An execution failure leaves the frozen source/policies available for a later retry.
  CurrentReviewResult[ReviewedCurrentState](status: CurrentReviewError.None,
    completed: ReviewedCurrentState(initialized: true, source: source.source, review: review.value))
proc failedCurrentReview[T, U](outcome: CurrentReviewResult[T]): CurrentReviewResult[
    U] {.requires: outcome.status != CurrentReviewError.None.} =
  ## Preserve every genuine failed alternative when a one-shot wrapper changes its successful payload type.
  case outcome.status
  of CurrentReviewError.ProfileFailure:
    # Preserve the exact original parameter-capture reason.
    CurrentReviewResult[U](status: CurrentReviewError.ProfileFailure,
        profileReason: outcome.profileReason)
  of CurrentReviewError.PreparationFailure:
    # Keep full report admission refusals separate from content execution.
    CurrentReviewResult[U](status: CurrentReviewError.PreparationFailure,
        preparationReason: outcome.preparationReason)
  of CurrentReviewError.ExecutionFailure:
    # Retain actual targeted predicate/join execution evidence.
    CurrentReviewResult[U](status: CurrentReviewError.ExecutionFailure,
        executionReason: outcome.executionReason)
  of CurrentReviewError.InvalidState:
    # A missing original qualified source cannot become a valid empty review.
    CurrentReviewResult[U](status: CurrentReviewError.InvalidState)
  of CurrentReviewError.InvalidPlan:
    # An invalid frozen owner retains its own refusal stage.
    CurrentReviewResult[U](status: CurrentReviewError.InvalidPlan)
  of CurrentReviewError.Uninitialized:
    # Default refusal remains explicitly uninitialized.
    CurrentReviewResult[U](status: CurrentReviewError.Uninitialized)
  of CurrentReviewError.None:
    assert false # The checked entry contract forbids dropping a successful original payload.
    CurrentReviewResult[U](status: CurrentReviewError.Uninitialized)
proc reviewCurrentState*(source: CurrentStateSerialization,
    limits: AccountReviewPlanLimits): CurrentReviewResult[ReviewedCurrentState] =
  ## Preserve the one-shot API while using the same frozen admission/execution path and original typed causes.
  let plan = planCurrentReview(source, limits)
  if plan.error != CurrentReviewError.None:
    return failedCurrentReview[CurrentReviewPlan, ReviewedCurrentState](plan)
  executeCurrentReview(plan.value)
proc reviewedCurrentSource*(source: ReviewedCurrentState): CurrentReviewResult[
    CurrentStateSerialization] =
  ## Retain the exact qualified source and its original parameter/producer chain.
  if not source.initialized:
    return CurrentReviewResult[CurrentStateSerialization](status: CurrentReviewError.Uninitialized)
  CurrentReviewResult[CurrentStateSerialization](status: CurrentReviewError.None,
      completed: source.source)
proc currentAccountReview*(source: ReviewedCurrentState): CurrentReviewResult[StateAccountReview] =
  ## Retain the same-inventory targeted observations without inferring a universal funding invariant.
  if not source.initialized:
    return CurrentReviewResult[StateAccountReview](status: CurrentReviewError.Uninitialized)
  CurrentReviewResult[StateAccountReview](status: CurrentReviewError.None, completed: source.review)
