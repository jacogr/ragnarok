# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict planned checkpoint payload/reason guards retain a genuine expected-root complete-review control.
import std/[assertions, cmdline, syncio]
import ../support/[state_inventory_context, planned_review_checkpoint_context, economic_profile_context]
import ../../src/chain/parameters
import ../../src/state/[planned_review_checkpoint, account_review, checkpoint, store, manifest, economic_profile]
import ../../src/codec/state_trie
include composition_fixture
proc extract(outcome: PlannedReviewCheckpointResult) {.noinline.} =
  ## No failed/default adapter result grants a review.
  discard outcome.value
proc guardSerialization(outcome: PlannedReviewCheckpointResult) {.noinline.} =
  ## Wrong alternatives invent no failed serialization stage.
  discard outcome.serializationFailure
proc guardInventory(outcome: PlannedReviewCheckpointResult) {.noinline.} =
  ## Wrong alternatives invent no failed inventory stage.
  discard outcome.inventoryFailure
proc guardPreparation(outcome: PlannedReviewCheckpointResult) {.noinline.} =
  ## Wrong alternatives invent no failed preparation stage.
  discard outcome.preparationFailure
proc guardExecution(outcome: PlannedReviewCheckpointResult) {.noinline.} =
  ## Wrong alternatives invent no failed execution stage.
  discard outcome.executionFailure
case paramStr(1)
of "default": extract(default(PlannedReviewCheckpointResult))
of "invalid": extract(decodePlannedReviewCheckpoint([], default(StateRoot), [], inventoryProfile,
    default(StateEconomicProfile), plannedReviewCheckpointTestLimits))
of "serialization": guardSerialization(default(PlannedReviewCheckpointResult))
of "inventory": guardInventory(default(PlannedReviewCheckpointResult))
of "preparation": guardPreparation(default(PlannedReviewCheckpointResult))
of "execution": guardExecution(default(PlannedReviewCheckpointResult))
of "ok":
  let services = inventoryServices()
  let original = inventoryManifest(compositionFixture(paramStr(2)), services).manifestSource.value
  let wire = encodeFullCheckpoint(original, plannedReviewCheckpointTestLimits.serialization.checkpointBytes).value
  let profile = captureEconomicProfile(decodeParameters(economicTestWire()).value).value
  let completed = decodePlannedReviewCheckpoint(wire, original.commitment.root, services,
      inventoryProfile, profile, plannedReviewCheckpointTestLimits)
  extract(completed)
  assert completed.value.accountReviewInfo.value.invariants.content.bytes == 3
  echo "state-planned-review-checkpoint-results: ok"
else: quit(2) # Unknown modes cannot satisfy intended guard evidence.
