# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict current-review guards use signed complete successor qualification as their genuine success control.
import std/[assertions, cmdline, syncio]
import ../support/[current_checkpoint_context, current_state_context,
    accumulation_current_chain_context, account_review_plan_context]
import ../../src/state/current/[review as current_review, state as current_state]
import ../../src/codec/report_owned
proc extract(outcome: CurrentReviewResult[ReviewedCurrentState]) {.noinline.} =
  ## Failed/default alternatives grant no completed owner.
  discard outcome.value
proc profile(outcome: CurrentReviewResult[ReviewedCurrentState]) {.noinline.} =
  ## No unrelated alternative invents a parameter refusal.
  discard outcome.profileError
proc preparation(outcome: CurrentReviewResult[ReviewedCurrentState]) {.noinline.} =
  ## Only real failed preparation carries a nested reason.
  discard outcome.preparationFailure
proc execution(outcome: CurrentReviewResult[ReviewedCurrentState]) {.noinline.} =
  ## Only real failed execution carries a nested reason.
  discard outcome.executionFailure
proc source(owner: ReviewedCurrentState) {.noinline.} =
  ## Default owners grant no qualified source.
  discard owner.reviewedCurrentSource.value
proc review(owner: ReviewedCurrentState) {.noinline.} =
  ## Default owners grant no completed targeted review.
  discard owner.currentAccountReview.value
proc main() {.raises.} =
  ## Trusted fixture reads belong only to the genuine positive control.
  case paramStr(1)
  of "default": extract(default(CurrentReviewResult[ReviewedCurrentState]))
  of "invalid": extract(reviewCurrentState(default(CurrentStateSerialization),
      reviewPlanTestLimits))
  of "profile": profile(default(CurrentReviewResult[ReviewedCurrentState]))
  of "preparation": preparation(default(CurrentReviewResult[ReviewedCurrentState]))
  of "execution": execution(default(CurrentReviewResult[ReviewedCurrentState]))
  of "source": source(default(ReviewedCurrentState))
  of "review": review(default(ReviewedCurrentState))
  of "ok":
    let raw = readFile(paramStr(2))
    var bytes = newSeq[byte](raw.len)
    for i in 0..<raw.len: bytes[i] = byte(raw[i])
    let qualified = currentQualifiedState(currentCheckpointPrepared(currentChainFixture(
        decodeOwnedReport(bytes, 2).value, available = true, completeState = true)))
    let completed = reviewCurrentState(qualified, reviewPlanTestLimits)
    extract(completed)
    source(completed.value)
    review(completed.value)
    echo "state-current-review-results: ok"
  else: quit(2) # Invalid selectors are not guard witnesses.
try:
  main()
except:
  quit(2) # Setup failure cannot stand in for an assertion/contract guard.
