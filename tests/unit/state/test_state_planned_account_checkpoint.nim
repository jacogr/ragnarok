# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Whole-account admission precedence and content-hash boundaries survive unchanged expected-root checkpoint restoration.
# @@Verification={"arc": "state_planned_account_checkpoint_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[state_inventory_context, planned_account_checkpoint_context, arc_evidence]
import ../../../src/state/[planned_account_checkpoint, validated_checkpoint, checkpoint, manifest, store,
  inventory, account_audit_plan, account_audit, account_invariants, preimage_content]
import ../../../src/codec/[bounded, state_trie, state_accounts, state_composition]
include ../../native/composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset hash counters or reject all primitive calls.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Separate mandatory restoration/capture hashes from account content hashes.
proc after(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Allow exact restoration/capture and reject the first content hash after successful planning.
proc cycle(wire: seq[byte], root: StateRoot, services: seq[StateService]) =
  ## Retire a complete restored audit graph inside one activation.
  let result = decodePlannedAccountCheckpoint(wire, root, services, inventoryProfile, plannedCheckpointTestLimits)
  assert result.error == PlannedAccountCheckpointError.None
proc main() {.raises.} =
  ## Build independent complete source and semantic-fault checkpoint before observer measurements.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  let source = inventoryManifest(fixture, services).manifestSource.value
  let root = source.commitment.root
  let wire = encodeFullCheckpoint(source, plannedCheckpointTestLimits.serialization.checkpointBytes).value
  services[0].metadata.storageItems = AccountStorageItems(4)
  let faulty = inventoryManifest(fixture, services).manifestSource.value
  let faultyWire = encodeFullCheckpoint(faulty, plannedCheckpointTestLimits.serialization.checkpointBytes).value
  services = inventoryServices()
  fail(0)
  let serialized = decodeValidatedCheckpoint(wire, root, services, inventoryProfile,
      plannedCheckpointTestLimits.serialization).value
  discard captureStateInventory(serialized, services, plannedCheckpointTestLimits.inventory).value
  let baseline = calls()
  fail(0)
  let result = decodePlannedAccountCheckpoint(wire, root, services, inventoryProfile, plannedCheckpointTestLimits)
  assert result.error == PlannedAccountCheckpointError.None and calls() == baseline+1
  let restored = result.value.accountInvariantInventory.value.inventorySource.value.manifestSource.value
  assert not sameStateSnapshot(restored, source)
  assert encodeFullCheckpoint(restored, plannedCheckpointTestLimits.serialization.checkpointBytes).value == wire
  var short = plannedCheckpointTestLimits
  short.audit.content.totalBytes = ByteLimit(2)
  fail(0)
  let refused = decodePlannedAccountCheckpoint(wire, root, services, inventoryProfile, short)
  assert refused.error == PlannedAccountCheckpointError.PlanningFailure and calls() == baseline
  assert refused.planningFailure.refusedPhase == AccountAuditRefusal.Content
  services[0].metadata.storageItems = AccountStorageItems(4)
  let admission = decodePlannedAccountCheckpoint(faultyWire, faulty.commitment.root, services,
      inventoryProfile, short)
  assert admission.error == PlannedAccountCheckpointError.PlanningFailure
  assert admission.planningFailure.refusedPhase == AccountAuditRefusal.Content
  let semantic = decodePlannedAccountCheckpoint(faultyWire, faulty.commitment.root, services,
      inventoryProfile, plannedCheckpointTestLimits)
  assert semantic.error == PlannedAccountCheckpointError.AuditFailure
  assert semantic.auditFailure.error == AccountAuditError.FootprintFailure
  services = inventoryServices()
  after(baseline)
  let backend = decodePlannedAccountCheckpoint(wire, root, services, inventoryProfile, plannedCheckpointTestLimits)
  assert backend.error == PlannedAccountCheckpointError.AuditFailure
  assert backend.auditFailure.contentFailure.error == PreimageContentError.BackendFailure
  fail(0)
  var wrongRoot = array[32, byte](root)
  wrongRoot[0] = wrongRoot[0] xor 1
  let untrusted = decodePlannedAccountCheckpoint(wire, StateRoot(wrongRoot), services,
      inventoryProfile, plannedCheckpointTestLimits)
  assert untrusted.error == PlannedAccountCheckpointError.SerializationFailure
  assert untrusted.serializationFailure.checkpointError == CheckpointError.RootMismatch
  short = plannedCheckpointTestLimits
  short.inventory.facts = ElementLimit(0)
  assert decodePlannedAccountCheckpoint(wire, root, services, inventoryProfile, short).error ==
      PlannedAccountCheckpointError.InventoryFailure
  for i in 0..<25: cycle(wire, root, services) # Warm complete expected-root restore/capture/admit/execute graphs.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(wire, root, services) # Retire every restored source and joined certificate.
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_planned_account_checkpoint", 1000, before, finalBytes)
  echo "state-planned-account-checkpoint: ok"
try:
  main()
except:
  quit(2) # Setup failure cannot qualify phase boundaries or lifetime evidence.
