# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed original-current review follows genuine collected supplied qualification and remains stable across separate adoption and joined shutdown.
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/app_collected_native_context
import ../../support/app_collected_logical_services_context
import ../../support/app_managed_supplied_context
import ../../support/state_current_logical_review_context
import ../../../src/app/services as app_services
import ../../../src/app/logical_review as app_logical_review
import ../../../src/app/current_block_input as app_current_block_input
import ../../../src/app/current_handoff as app_current_handoff
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/current_state as state_current_state
import ../../../src/state/current_review as state_current_review
import ../../../src/state/account_review as state_account_review
import ../../../src/state/inventory as state_inventory
import ../../../src/state/manifest as state_manifest
import ../../../src/state/store as state_store
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
