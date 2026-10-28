# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Expected-root restoration exposes targeted account evidence only after each independently bounded phase completes.
# @@Verification={"arc": "state_account_checkpoint_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_inventory_context
import ../../support/state_account_checkpoint_context
import ../../support/testing_arc_evidence
import ../../../src/state/account_checkpoint as state_account_checkpoint
import ../../../src/state/validated_checkpoint as state_validated_checkpoint
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/state/store as state_store
import ../../../src/state/manifest as state_manifest
import ../../../src/state/inventory as state_inventory
import ../../../src/state/account_invariants as state_account_invariants
import ../../../src/state/footprint_audit as state_footprint_audit
import ../../../src/state/preimage_linkage as state_preimage_linkage
import ../../../src/state/preimage_content as state_preimage_content
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_requests as codec_state_requests
import ../../../src/codec/state_composition as codec_state_composition
include ../../native/nimony_composition_fixture
proc cycle(wire: seq[byte], root: StateRoot, services: seq[StateService]) =
  ## Retire the entire restored graph and every joined certificate inside one activation.
  let result = decodeAccountCheckpoint(wire, root, services, inventoryProfile, accountCheckpointLimits)
  assert result.error == AccountCheckpointError.None
  assert result.value.accountInvariantInfo.value.content.bytes == 3
  assert array[32, byte](result.value.accountInvariantInventory.value.inventorySource.value.manifestSource.value.commitment.root) ==
      array[32, byte](root)
proc checkVariant(fixture: seq[seq[byte]], services: seq[StateService]): AccountCheckpointResult =
  ## Serialize an independently complete map around a selected semantic account fault.
  let source = inventoryManifest(fixture, services).manifestSource.value
  let wire = encodeFullCheckpoint(source, accountCheckpointLimits.serialization.checkpointBytes).value
  decodeAccountCheckpoint(wire, source.commitment.root, services, inventoryProfile, accountCheckpointLimits)
proc main() {.raises.} =
  ## Separate trusted expected root selection from embedded checkpoint identity and restored source owners.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  let source = inventoryManifest(fixture, services).manifestSource.value
  let wire = encodeFullCheckpoint(source, accountCheckpointLimits.serialization.checkpointBytes).value
  let root = source.commitment.root
  var disposable = newSeq[byte](wire.len)
  for i in 0..<wire.len: disposable[i] = wire[i] # Own a caller buffer that will be destroyed after synchronous decoding.
  let result = decodeAccountCheckpoint(disposable, root, services, inventoryProfile, accountCheckpointLimits)
  assert result.error == AccountCheckpointError.None
  for i in 0..<disposable.len: disposable[i] = 0 # Mutate every borrowed byte after completion.
  disposable = @[]
  let restored = result.value.accountInvariantInventory.value.inventorySource.value.manifestSource.value
  assert not sameStateSnapshot(restored, source)
  assert encodeFullCheckpoint(restored, accountCheckpointLimits.serialization.checkpointBytes).value == wire
  var wrongRoot = array[32, byte](root)
  wrongRoot[0] = wrongRoot[0] xor 1
  let untrusted = decodeAccountCheckpoint(wire, StateRoot(wrongRoot), services, inventoryProfile, accountCheckpointLimits)
  assert untrusted.error == AccountCheckpointError.SerializationFailure
  assert untrusted.serializationFailure.checkpointError == CheckpointError.RootMismatch
  let mismatch = decodeAccountCheckpoint(wire, root, [], inventoryProfile, accountCheckpointLimits)
  assert mismatch.error == AccountCheckpointError.SerializationFailure
  assert mismatch.serializationFailure.manifestFailure.error == StateManifestError.MappingMismatch
  var short = accountCheckpointLimits
  short.inventory.facts = ElementLimit(0)
  let captureRefused = decodeAccountCheckpoint(wire, root, services, inventoryProfile, short)
  assert captureRefused.error == AccountCheckpointError.InventoryFailure
  assert captureRefused.inventoryFailure.error == StateInventoryError.LimitExceeded
  short = accountCheckpointLimits
  short.footprints.checks = ElementLimit(3)
  let footprintRefused = decodeAccountCheckpoint(wire, root, services, inventoryProfile, short)
  assert footprintRefused.error == AccountCheckpointError.FootprintFailure
  assert footprintRefused.footprintFailure.error == FootprintAuditError.LimitExceeded
  short = accountCheckpointLimits
  short.linkage.comparisons = ElementLimit(0)
  let linkageRefused = decodeAccountCheckpoint(wire, root, services, inventoryProfile, short)
  assert linkageRefused.error == AccountCheckpointError.LinkageFailure
  assert linkageRefused.linkageFailure.error == PreimageLinkageError.LimitExceeded
  short = accountCheckpointLimits
  short.content.totalBytes = ByteLimit(2)
  let contentRefused = decodeAccountCheckpoint(wire, root, services, inventoryProfile, short)
  assert contentRefused.error == AccountCheckpointError.ContentFailure
  assert contentRefused.contentFailure.error == PreimageContentError.LimitExceeded
  services[0].metadata.storageItems = AccountStorageItems(4)
  let badFootprint = checkVariant(fixture, services)
  assert badFootprint.error == AccountCheckpointError.FootprintFailure
  assert badFootprint.footprintFailure.error == FootprintAuditError.ItemsMismatch
  services = inventoryServices()
  services[0].requests[0].length = RequestLength(2)
  services[0].metadata.storageBytes = AccountStorageBytes(120)
  let badLinkage = checkVariant(fixture, services)
  assert badLinkage.error == AccountCheckpointError.LinkageFailure
  assert badLinkage.linkageFailure.error == PreimageLinkageError.MissingRequest
  services = inventoryServices()
  services[0].preimages[0].value[0] = 98
  let badContent = checkVariant(fixture, services)
  assert badContent.error == AccountCheckpointError.ContentFailure
  assert badContent.contentFailure.error == PreimageContentError.HashMismatch
  services = inventoryServices()
  let untouched = default(AccountCheckpointResult)
  assert untouched.error == AccountCheckpointError.Uninitialized
  for i in 0..<25: cycle(wire, root, services) # Warm the full restoration/capture/predicate retirement path.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(wire, root, services) # All restored owner graphs retire without retaining caller buffers or certificates.
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_account_checkpoint", 1000, before, finalBytes)
  echo "state-account-checkpoint: ok"
try:
  main()
except:
  quit(2) # Setup refusal never qualifies restored ownership evidence.
