# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete restoration prepares reports before content work and preserves root authority, precise phase errors and retired ownership.
# @@Verification={"arc": "state_planned_review_checkpoint_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_inventory_context
import ../../support/state_planned_review_checkpoint_context
import ../../support/state_economic_profile_context
import ../../support/testing_arc_evidence
import ../../../src/chain/parameters as chain_parameters
import ../../../src/state/planned_review_checkpoint as state_planned_review_checkpoint
import ../../../src/state/account_review_plan as state_account_review_plan
import ../../../src/state/account_review as state_account_review
import ../../../src/state/validated_checkpoint as state_validated_checkpoint
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/state/store as state_store
import ../../../src/state/inventory as state_inventory
import ../../../src/state/manifest as state_manifest
import ../../../src/state/economic_profile as state_economic_profile
import ../../../src/state/service_directory as state_service_directory
import ../../../src/state/economics_table as state_economics_table
import ../../../src/state/preimage_content as state_preimage_content
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_accounts as codec_state_accounts
include ../../native/nimony_composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset observer work and optionally refuse all hash operations.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Compare mandatory restoration/capture work separately from one content hash.
proc after(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Allow exactly the measured mandatory hashes, then refuse the first account-content operation.
proc cycle(wire: seq[byte], root: StateRoot, services: seq[StateService],
    profile: StateEconomicProfile) =
  ## Restore and retire one full prepared-review graph per cycle, preserving successful coverage observations.
  let review = decodePlannedReviewCheckpoint(wire, root, services, inventoryProfile, profile,
      plannedReviewCheckpointTestLimits).value
  assert review.accountReviewInfo.value.economics.uncovered == 1
proc main() {.raises.} =
  ## Genuine complete typed sources include an undercovered account; that observation remains successful.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  services[0].metadata.balance = AccountBalance(100)
  let original = inventoryManifest(fixture, services).manifestSource.value
  let root = original.commitment.root
  let wire = encodeFullCheckpoint(original, plannedReviewCheckpointTestLimits.serialization.checkpointBytes).value
  let profile = captureEconomicProfile(decodeParameters(economicTestWire()).value).value
  let overflow = captureEconomicProfile(decodeParameters(economicTestWire(0, 0, high(
      uint64))).value).value
  fail(1)
  let missing = decodePlannedReviewCheckpoint(wire, root, services, inventoryProfile, default(
      StateEconomicProfile), plannedReviewCheckpointTestLimits)
  assert missing.error == PlannedReviewCheckpointError.InvalidProfile and calls() == 0
  fail(0)
  var short = plannedReviewCheckpointTestLimits
  short.review.directory.bytes = ByteLimit(0)
  let directory = decodePlannedReviewCheckpoint(wire, root, services, inventoryProfile, profile, short)
  assert directory.error == PlannedReviewCheckpointError.PreparationFailure
  assert directory.preparationFailure.error == AccountReviewPlanError.DirectoryFailure
  assert directory.preparationFailure.directoryFailure.error == ServiceDirectoryError.LimitExceeded
  let mandatory = calls()
  assert mandatory > 0
  fail(0)
  let completed = decodePlannedReviewCheckpoint(wire, root, services, inventoryProfile, profile, plannedReviewCheckpointTestLimits)
  assert completed.error == PlannedReviewCheckpointError.None and calls() == mandatory+1
  assert completed.value.accountReviewInfo.value.economics.uncovered == 1
  assert sameEconomicProfile(completed.value.reviewEconomicProfile.value, profile)
  fail(0)
  let arithmetic = decodePlannedReviewCheckpoint(wire, root, services, inventoryProfile, overflow, plannedReviewCheckpointTestLimits)
  assert arithmetic.error == PlannedReviewCheckpointError.PreparationFailure and calls() == mandatory
  assert arithmetic.preparationFailure.error == AccountReviewPlanError.EconomicsFailure
  assert arithmetic.preparationFailure.economicsFailure.error ==
      EconomicsTableError.ObservationFailure
  after(mandatory)
  let backend = decodePlannedReviewCheckpoint(wire, root, services, inventoryProfile, profile, plannedReviewCheckpointTestLimits)
  assert backend.error == PlannedReviewCheckpointError.ExecutionFailure
  assert backend.executionFailure.error == AccountReviewExecutionError.ContentFailure
  assert backend.executionFailure.contentFailure.error == PreimageContentError.BackendFailure
  fail(0)
  short = plannedReviewCheckpointTestLimits
  short.inventory.facts = ElementLimit(0)
  let capture = decodePlannedReviewCheckpoint(wire, root, services, inventoryProfile, profile, short)
  assert capture.error == PlannedReviewCheckpointError.InventoryFailure
  assert capture.inventoryFailure.error == StateInventoryError.LimitExceeded
  var wrong = array[32, byte](root)
  wrong[0] = wrong[0] xor 1
  let refused = decodePlannedReviewCheckpoint(wire, StateRoot(wrong), services, inventoryProfile,
      profile, plannedReviewCheckpointTestLimits)
  assert refused.error == PlannedReviewCheckpointError.SerializationFailure
  assert refused.serializationFailure.error == ValidatedCheckpointError.CheckpointFailure
  assert refused.serializationFailure.checkpointError == CheckpointError.RootMismatch
  let mismatch = decodePlannedReviewCheckpoint(wire, root, [], inventoryProfile, profile, plannedReviewCheckpointTestLimits)
  assert mismatch.error == PlannedReviewCheckpointError.SerializationFailure
  assert mismatch.serializationFailure.error == ValidatedCheckpointError.ManifestFailure
  assert mismatch.serializationFailure.manifestFailure.error == StateManifestError.MappingMismatch
  var disposable = newSeq[byte](wire.len)
  for i in 0..<wire.len: disposable[i] = wire[i]
  let detached = decodePlannedReviewCheckpoint(disposable, root, services, inventoryProfile,
      profile, plannedReviewCheckpointTestLimits).value
  for i in 0..<disposable.len: disposable[i] = 0
  disposable = @[]
  assert encodeFullCheckpoint(detached.reviewInventory.value.inventorySource.value.manifestSource.value,
      plannedReviewCheckpointTestLimits.serialization.checkpointBytes).value == wire
  for i in 0..<25: cycle(wire, root, services, profile)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(wire, root, services, profile)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_planned_review_checkpoint", 1000, before, finalBytes)
  echo "state-planned-review-checkpoint: ok"
try:
  main()
except:
  quit(2) # Fixture/setup failure cannot qualify restoration, phase or retirement evidence.
