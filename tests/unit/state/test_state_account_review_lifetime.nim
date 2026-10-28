# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Restored review evidence survives caller-buffer destruction, component handle drops and independent mutable forks.
# @@Verification={"arc": "state_account_review_lifetime_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_inventory_context
import ../../support/state_account_review_checkpoint_context
import ../../support/state_economic_profile_context
import ../../support/testing_arc_evidence
import ../../../src/chain/parameters as chain_parameters
import ../../../src/state/account_review_checkpoint as state_account_review_checkpoint
import ../../../src/state/account_review as state_account_review
import ../../../src/state/economic_profile as state_economic_profile
import ../../../src/state/inventory as state_inventory
import ../../../src/state/manifest as state_manifest
import ../../../src/state/store as state_store
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/codec/state_trie as codec_state_trie
include ../../native/nimony_composition_fixture
proc retainedSource(wire: seq[byte], root: StateRoot, services: seq[StateService],
    profile: StateEconomicProfile): StateStoreSnapshot =
  ## Drop every review/component owner and caller byte buffer before returning only the independently retained immutable source.
  var disposable = newSeq[byte](wire.len)
  for i in 0..<wire.len: disposable[i] = wire[i] # Force uniquely owned caller transport before synchronous decode.
  var left = decodeAccountReviewCheckpoint(disposable, root, services, inventoryProfile, profile,
      accountReviewCheckpointTestLimits).value
  for i in 0..<disposable.len: disposable[i] = 255 # Invalidate all original caller framing and payload bytes.
  disposable = @[]
  var right = left
  assert sameStateInventory(left.reviewInventory.value, right.reviewInventory.value)
  left = default(StateAccountReview)
  assert left.accountReviewInfo.error == AccountReviewError.Uninitialized
  let inventory = right.reviewInventory.value
  var copied = right.accountReviewInfo.value
  copied.economics.uncovered = 999
  assert right.accountReviewInfo.value.economics.uncovered == 1
  assert sameEconomicProfile(right.reviewEconomicProfile.value, profile)
  right = default(StateAccountReview)
  assert right.reviewInventory.error == AccountReviewError.Uninitialized
  let source = inventory.inventorySource.value.manifestSource.value
  let key = inventory.inventoryPreimageAt(InventoryServiceIndex(0), InventoryPreimageIndex(0)).value.key
  var payload = source.lookup(key).value.bytes
  assert payload == @[byte(97), 98, 99]
  payload[0] = 0
  assert source.lookup(key).value.bytes == @[byte(97), 98, 99]
  source
proc cycle(wire: seq[byte], root: StateRoot, services: seq[StateService],
    profile: StateEconomicProfile) =
  ## A private mutable fork may publish a successor without changing the retained original after all review handles retired.
  let source = retainedSource(wire, root, services, profile)
  assert array[32, byte](source.commitment.root) == array[32, byte](root)
  var branch = forkStateStore(source).value
  var changedMetadata = services[0].metadata
  changedMetadata.balance = AccountBalance(0)
  let changed = serviceMetadataEntry(services[0].service, changedMetadata, ByteLimit(105)).value
  let successor = branch.apply([StateWrite(key: changed.key, kind: StateWriteKind.Put,
      value: changed.value)]).value
  assert array[32, byte](successor.commitment.root) != array[32, byte](root)
  assert source.lookup(changed.key).value.bytes != changed.value
  assert encodeFullCheckpoint(source, accountReviewCheckpointTestLimits.checkpoint.serialization.checkpointBytes).value == wire
proc main() {.raises.} =
  ## Keep fixed source fixture inputs while every cycle creates/retires independent restored review and fork graphs.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  services[0].metadata.balance = AccountBalance(100)
  let source = inventoryManifest(fixture, services).manifestSource.value
  let root = source.commitment.root
  let wire = encodeFullCheckpoint(source, accountReviewCheckpointTestLimits.checkpoint.serialization.checkpointBytes).value
  let profile = captureEconomicProfile(decodeParameters(economicTestWire()).value).value
  for i in 0..<25: cycle(wire, root, services, profile) # Warm exact detached decode/drop/fork/retirement allocation shapes.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(wire, root, services, profile) # No old review, copied payload, restored snapshot or mutable successor accumulates.
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_account_review_lifetime", 1000, before, finalBytes)
  echo "state-account-review-lifetime: ok"
try:
  main()
except:
  quit(2) # Setup failure cannot qualify detached ownership or allocation retirement.
