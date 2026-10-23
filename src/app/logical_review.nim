# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Pair complete logical provenance with review of only its original current compact inventory and Parameters.
import ../state/[current_logical, current_review, account_review_plan]
type
  ReviewedLogicalState* = object ## Private pair cannot cross-join independently revalidated raw-key compact evidence.
    initialized: bool
    logical: CurrentLogicalState
    reviewed: ReviewedCurrentState
  LogicalReviewError* {.pure.} = enum ## Default/invalid logical source and actual original-current review refusal stay distinct.
    Uninitialized, None, InvalidLogical, ReviewFailure
  LogicalReviewResult*[T] = object ## No refused component exposes a completed pair or predicate prefix.
    case status: LogicalReviewError
    of None: completed: T
    of ReviewFailure: reviewReason: CurrentReviewResult[ReviewedCurrentState]
    else: discard # No default or invalid source supplies a pair.
func error*[T](outcome: LogicalReviewResult[T]): LogicalReviewError =
  ## Observe only immutable selected alternatives.
  outcome.status
func value*[T](outcome: LogicalReviewResult[T]): T {.inline, requires: outcome.status ==
    LogicalReviewError.None.} =
  ## Extract only the completed original-source pair or a guarded retained member.
  outcome.completed
func reviewFailure*[T](outcome: LogicalReviewResult[T]): CurrentReviewResult[
    ReviewedCurrentState] {.inline, requires: outcome.status == LogicalReviewError.ReviewFailure.} =
  ## Preserve original parameter, admission and targeted predicate execution failures.
  outcome.reviewReason
proc reviewLogicalState*(source: CurrentLogicalState,
    limits: AccountReviewPlanLimits): LogicalReviewResult[ReviewedLogicalState] =
  ## Only original current serialization supplies review input; caller cannot replace economic rates or substitute the raw-key compact capture.
  let current = source.currentLogicalSource
  if current.error != CurrentLogicalError.None:
    return LogicalReviewResult[ReviewedLogicalState](status: LogicalReviewError.InvalidLogical)
  let reviewed = reviewCurrentState(current.value, limits)
  if reviewed.error != CurrentReviewError.None:
    return LogicalReviewResult[ReviewedLogicalState](status: LogicalReviewError.ReviewFailure,
        reviewReason: reviewed)
  LogicalReviewResult[ReviewedLogicalState](status: LogicalReviewError.None,
    completed: ReviewedLogicalState(initialized: true, logical: source, reviewed: reviewed.value))
proc reviewedLogicalSource*(source: ReviewedLogicalState): LogicalReviewResult[
    CurrentLogicalState] =
  ## Retain original complete logical/source/raw-key provenance without granting a mixed-inventory join.
  if not source.initialized:
    return LogicalReviewResult[CurrentLogicalState](status: LogicalReviewError.Uninitialized)
  LogicalReviewResult[CurrentLogicalState](status: LogicalReviewError.None,
      completed: source.logical)
proc logicalCurrentReview*(source: ReviewedLogicalState): LogicalReviewResult[
    ReviewedCurrentState] =
  ## Retain only the targeted report certified on the original current compact inventory and actual full Parameters.
  if not source.initialized:
    return LogicalReviewResult[ReviewedCurrentState](status: LogicalReviewError.Uninitialized)
  LogicalReviewResult[ReviewedCurrentState](status: LogicalReviewError.None,
      completed: source.reviewed)
