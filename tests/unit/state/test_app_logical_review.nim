# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Logical review keeps original compact identity and full economic provenance distinct from the retained raw-key companion.
import std/assertions
import std/syncio
import ../../support/app_collected_native_context
import ../../support/app_collected_supplied_context
import ../../support/state_current_logical_review_context
import ../../../src/app/logical_review as app_logical_review
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/current_state as state_current_state
import ../../../src/state/current_review as state_current_review
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../../src/state/inventory as state_inventory
import ../../../src/state/account_review as state_account_review
import ../../../src/state/account_review_plan as state_account_review_plan
import ../../../src/codec/bounded as codec_bounded
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Fault actual content predicates only after real supplied qualification and original source capture.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Admission refusal must precede all content primitives.
proc main() {.raises.} =
  ## Actual collected logical output supplies the original current inventory; no detached companion certificate is joined into its review.
  let fixture = collectedNativeFixture()
  let logical = suppliedNativeState(fixture)
  let pair = reviewLogicalState(logical, logicalReviewTestLimits()).value
  let review = pair.logicalCurrentReview.value.currentAccountReview.value
  assert sameStateInventory(review.reviewInventory.value,
      logical.currentLogicalSource.value.currentStateInventory.value)
  assert not sameStateInventory(review.reviewInventory.value,
      logical.currentLogicalInventory.value.suppliedInventory.value)
  assert review.accountReviewInfo.value.invariants.content.preimages == 6
  assert review.accountReviewInfo.value.economics.covered == 2
  fail(1)
  var short = logicalReviewTestLimits()
  short.audit.planning = ElementLimit(0)
  assert reviewLogicalState(logical, short).reviewFailure.error ==
      CurrentReviewError.PreparationFailure
  assert calls() == 0
  let backend = reviewLogicalState(logical, logicalReviewTestLimits())
  assert backend.reviewFailure.error == CurrentReviewError.ExecutionFailure
  fail(0)
  let empty = default(CurrentLogicalState)
  assert reviewLogicalState(empty, logicalReviewTestLimits()).error ==
      LogicalReviewError.InvalidLogical
  let missing = default(ReviewedLogicalState)
  assert missing.reviewedLogicalSource.error == LogicalReviewError.Uninitialized
  assert missing.logicalCurrentReview.error == LogicalReviewError.Uninitialized
  echo "application-logical-review: ok"
try:
  main()
except:
  quit(2) # Original same-inventory predicate failure cannot supply a reviewed logical prefix.
