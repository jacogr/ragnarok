# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine completed current logical state advances across three authenticated empty children with complete namespaces and original full-view provenance.
# @@Verification={"arc":"state_current_refresh_repeated_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_current_repeated_logical_context
import ../../support/state_current_namespace_refresh_context
import ../../support/state_supplied_services_context
import ../../support/testing_arc_evidence
import ../../../src/state/current_identities as state_current_identities
import ../../../src/state/current_request_keys as state_current_request_keys
import ../../../src/state/current_refresh_plan as state_current_refresh_plan
import ../../../src/state/current_logical_refresh as state_current_logical_refresh
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/current_state as state_current_state
import ../../../src/state/current_globals as state_current_globals
import ../../../src/state/current_profile as state_current_profile
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../../src/state/supplied_services as state_supplied_services
import ../../../src/state/inventory as state_inventory
import ../../../src/state/manifest as state_manifest
import ../../../src/state/store as state_store
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Every actual child preparation and key derivation completes before its hash-free frozen-plan assertions.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Complete current matching deliberately hashes; fixed identity/frozen admission/projection cannot.
proc verify(source: CurrentLogicalState, update: PreparedCurrentChainUpdate, slot: uint32) =
  ## Existing complete current/private profile and both compact captures remain tied to this exact actual producer at the new slot.
  let inventory = source.currentLogicalInventory.value.suppliedInventory.value
  let producer = source.currentLogicalSource.value.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedUpdate.value
  assert sameStateSnapshot(producer.currentUpdateState, update.currentUpdateState)
  assert sameStateSnapshot(inventory.inventorySource.value.manifestSource.value,
      update.currentUpdateState)
  for i in 0..<2:
    let row = inventory.inventoryServiceAt(InventoryServiceIndex(uint64(i))).value
    assert uint32(row.metadata.lastAccumulation) == slot and uint32(row.metadata.storageItems) == 8
    assert row.storage == 2 and row.preimages == 3 and row.requests == 3
proc cycle(plan: CurrentLogicalRefreshPlan, update: PreparedCurrentChainUpdate) =
  ## Retire both new inventories and full detached code/raw-key arrays while preserving the genuine final child and previous owner graphs.
  let completed = executeCurrentLogicalRefresh(plan).value
  verify(completed, update, 5)
  assert copySuppliedServices(completed.currentLogicalInventory.value,
      suppliedServicesTestLimits).value.len == 2
proc main() {.raises.} =
  ## The maintained signer only authors bounded first-epoch empty bodies; every child is actually prepared through the current pipeline.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let fixture = repeatedLogicalFixture(decodeOwnedReport(bytes, 2).value)
  var prior = fixture.logical
  var update = fixture.next
  var last = default(CurrentLogicalRefreshPlan)
  for slot in 3'u32..5'u32:
    let previous = prior.currentLogicalSource.value.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedUpdate.value
    let stages = namespaceRefreshStages(prior, update)
    assert stages.identities.identityParent.error == CurrentIdentityError.WrongSource
    assert sameStateInventory(stages.identities.identityPriorCurrent.value.currentLogicalInventory.value.suppliedInventory.value,
        prior.currentLogicalInventory.value.suppliedInventory.value)
    assert sameStateSnapshot(update.currentUpdatePriorState, previous.currentUpdateState)
    fail(1)
    assert planCurrentRefresh(stages.keys, namespaceRefreshLimits).error ==
        CurrentRefreshPlanError.None
    let planned = planCurrentLogicalRefresh(stages.reconstruction, namespaceLogicalLimits()).value
    assert planned.logicalRefreshPlanInfo.value.entries == 34 and
        planned.logicalRefreshPlanInfo.value.checks == 40
    assert stages.reconstruction.refreshPlanInfo.value.wireBytes == 240 and calls() == 0
    fail(0)
    let completed = executeCurrentLogicalRefresh(planned).value
    verify(completed, update, slot)
    assert update.currentUpdateViewInfo.history == int(slot)
    last = planned
    prior = completed
    if slot < 5:
      update = nextLogicalEmpty(update) # Actual next-parent snapshots, full ordered views and signatures come only from the preceding genuine update.
  assert update.currentUpdateChildContext.slot == 5
  for i in 0..<25: cycle(last, update)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(last, update)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_current_refresh_repeated", 1000, before, finalBytes)
  echo "state-current-refresh-repeated: ok"
try:
  main()
except:
  quit(2) # No equal-root replacement, startup rewrap or legacy completion certificate can substitute real consecutive current qualification.
