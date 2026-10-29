# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed original-current review follows genuine collected supplied qualification and remains stable across separate adoption and joined shutdown.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[collected_native_context, collected_logical_services_context,
    managed_supplied_context,
    current_logical_review_context]
import ../../../src/app/services
import ../../../src/app/logical/review as logical_review
import "../../../src/app/current/block/input" as current_block_input
import ../../../src/app/current/handoff as current_handoff
import ../../../src/state/current/[logical as current_logical, state as current_state,
    review as current_review]
import ../../../src/state/account/review as account_review
import ../../../src/state/[inventory, manifest, store]
proc main() {.raises.} =
  ## Genuine current preparation finishes its actual managed lease before any logical predicate or report work begins.
  let fixture = collectedNativeFixture()
  var owner = default(Services)
  var input = default(CurrentBlockInput)
  var path = "application-managed-logical-review-chain.json"
  discard startLogicalServices(owner, fixture.fixture, path)
  defer:
    owner.close()
    discard posix.unlink(path.toCString())
  let logical = collectManagedSupplied(owner, input, fixture.fixture)
  let pair = owner.reviewLogicalState(logical, logicalReviewTestLimits()).value
  let report = pair.logicalCurrentReview.value.currentAccountReview.value
  assert sameStateInventory(report.reviewInventory.value,
      logical.currentLogicalSource.value.currentStateInventory.value)
  assert owner.enqueueCurrentAccumulation(logical.currentLogicalUpdate.value) ==
      CurrentHandoffAdmission.None
  owner.tick(0)
  assert owner.takeCurrentAccumulation.error == CurrentHandoffError.None
  owner.close()
  assert pair.logicalCurrentReview.value.currentAccountReview.value.accountReviewInfo.value.invariants.content.preimages == 6
  assert sameStateSnapshot(report.reviewInventory.value.inventorySource.value.manifestSource.value,
      logical.currentLogicalContext.value.state)
  echo "application-managed-logical-review: ok"
try:
  main()
except:
  quit(2) # Neither adoption nor shutdown substitutes report provenance or grants cross-capture joins.
