# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic restored-review payload/phase guards retain genuine explicit-root and explicit-policy success as a control.
import std/[assertions, cmdline, syncio]
import ../support/[state_inventory_context, account_review_checkpoint_context, economic_profile_context]
import ../../src/chain/parameters
import ../../src/state/[account_review_checkpoint, account_review, economic_profile, checkpoint,
    store, manifest]
include composition_fixture
proc extract(outcome: AccountReviewCheckpointResult): StateAccountReview {.noinline.} =
  ## Default or failed restoration grants no composite review owner.
  outcome.value
proc guardCheckpoint(outcome: AccountReviewCheckpointResult) {.noinline.} =
  ## Default results invent no failed checkpoint stage.
  discard outcome.checkpointFailure
proc guardDirectory(outcome: AccountReviewCheckpointResult) {.noinline.} =
  ## Default results invent no failed directory stage.
  discard outcome.directoryFailure
proc guardFootprint(outcome: AccountReviewCheckpointResult) {.noinline.} =
  ## Default results invent no failed footprint stage.
  discard outcome.footprintFailure
proc guardSupervision(outcome: AccountReviewCheckpointResult) {.noinline.} =
  ## Default results invent no failed supervision stage.
  discard outcome.supervisionFailure
proc guardEconomics(outcome: AccountReviewCheckpointResult) {.noinline.} =
  ## Default results invent no failed economics stage.
  discard outcome.economicsFailure
proc guardReview(outcome: AccountReviewCheckpointResult) {.noinline.} =
  ## Default results invent no failed review stage.
  discard outcome.reviewFailure
case paramStr(1)
of "default": discard extract(default(AccountReviewCheckpointResult)) # No default payload.
of "checkpoint": guardCheckpoint(default(AccountReviewCheckpointResult)) # No invented stage.
of "directory": guardDirectory(default(AccountReviewCheckpointResult)) # No invented stage.
of "footprint": guardFootprint(default(AccountReviewCheckpointResult)) # No invented stage.
of "supervision": guardSupervision(default(AccountReviewCheckpointResult)) # No invented stage.
of "economics": guardEconomics(default(AccountReviewCheckpointResult)) # No invented stage.
of "review": guardReview(default(AccountReviewCheckpointResult)) # No invented stage.
of "ok":
  let services = inventoryServices()
  let source = inventoryManifest(compositionFixture(paramStr(2)), services).manifestSource.value
  let wire = encodeFullCheckpoint(source, accountReviewCheckpointTestLimits.checkpoint.serialization.checkpointBytes).value
  let profile = captureEconomicProfile(decodeParameters(economicTestWire()).value).value
  let review = extract(decodeAccountReviewCheckpoint(wire, source.commitment.root, services,
      inventoryProfile, profile, accountReviewCheckpointTestLimits))
  assert review.accountReviewInfo.value.invariants.content.bytes == 3
  echo "state-account-review-checkpoint-results: ok"
else: quit(2) # Unknown selectors cannot satisfy controls.
