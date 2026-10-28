# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Test-only composition for the agreed collection-before-enqueue consumer; no new public review adapter, predicate or policy.
import std/assertions
import ./state_account_review_plan_context
import ../../src/state/current_logical as state_current_logical
import ../../src/state/current_state as state_current_state
import ../../src/state/current_review as state_current_review
import ../../src/state/account_review_plan as state_account_review_plan
import ../../src/state/account_review as state_account_review
import ../../src/state/inventory as state_inventory
import ../../src/state/account_audit_plan as state_account_audit_plan
import ../../src/state/footprint_audit as state_footprint_audit
import ../../src/state/preimage_content as state_preimage_content
import ../../src/state/preimage_linkage as state_preimage_linkage
import ../../src/codec/bounded as codec_bounded
type CurrentLogicalReviewComposition* = object ## Test descriptors keep original complete logical provenance beside the existing current-source review, without joining different compact captures.
  logical*: CurrentLogicalState
  reviewed*: ReviewedCurrentState
proc logicalReviewTestLimits*(): AccountReviewPlanLimits =
  ## Complete code namespaces need six preimages/requests; existing report predicates and original-parameter selection remain unchanged.
  result = reviewPlanTestLimits
  result.audit = AccountAuditLimits(planning: ElementLimit(10), footprints: FootprintAuditLimits(
      services: ElementLimit(2), checks: ElementLimit(12)), content: PreimageContentLimits(
      services: ElementLimit(2), preimages: ElementLimit(6), perValue: ByteLimit(65536),
      totalBytes: ByteLimit(262144)), linkage: PreimageLinkageLimits(services: ElementLimit(2),
      preimages: ElementLimit(6), comparisons: ElementLimit(18)))
proc composeLogicalReview*(logical: CurrentLogicalState): CurrentLogicalReviewComposition =
  ## Only the logical owner's original current serialization supplies review input; the raw-key companion remains a separate capture.
  let source = logical.currentLogicalSource.value
  let reviewed = reviewCurrentState(source, logicalReviewTestLimits()).value
  assert sameStateInventory(reviewed.currentAccountReview.value.reviewInventory.value,
      source.currentStateInventory.value)
  CurrentLogicalReviewComposition(logical: logical, reviewed: reviewed)
