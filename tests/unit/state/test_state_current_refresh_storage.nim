# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine funded current storage growth refreshes actual payload/footprint while preserving raw identities and refusing stale-length copy budgets.
# @@Verification={"arc":"state_current_refresh_storage_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_namespace_transition_context, current_namespace_execution_context,
    current_namespace_context, current_namespace_refresh_context, accumulation_execution_context,
    supplied_services_context, arc_evidence]
import ../../../src/state/parent/logical as parent_logical
import ../../../src/state/current/[identities as current_identities,
    request_keys as current_request_keys]
import ../../../src/state/current/refresh/plan as current_refresh_plan
import ../../../src/state/current/logical/refresh as current_logical_refresh
import ../../../src/state/current/logical as current_logical
import ../../../src/state/supplied/[logical_inventory as supplied_logical_inventory,
    services as supplied_services]
import ../../../src/state/[inventory, manifest, store]
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/codec/[bounded, report_owned]
import ../../../src/codec/state/[accounts as state_accounts, composition as state_composition,
    service_values as state_service_values]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## All actual code/parent/current execution and request-key derivation precede hash-free actual-extent policy checks.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Cached target extent planning and detached projection cannot hash.
proc cycle(plan: CurrentLogicalRefreshPlan, expected: openArray[byte]) =
  ## Retire updated full inventories and complete detached payload copies after each genuine source-bound refresh.
  let logical = executeCurrentLogicalRefresh(plan).value
  let services = copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  assert services[1].storage[1].value.len == expected.len
  for i in 0..<expected.len:
    assert services[1].storage[1].value[i] == expected[
        i] # Exact original actual target bytes survive every copied array lifetime.
proc main() {.raises.} =
  ## Existing guest host-write convention executes only against funded99, with the original key and counters committed before signing.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  var value = newSeq[byte](65)
  for i in 0..<value.len: value[i] = byte(i+21) # Independently authored increasing octets fit the byte domain without wrapping.
  let code = namespaceStorageCode(value)
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondProgram = code
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  options.signed.serviceNamespaces[1].storage[1] = StateStorageItem(key: @[7'u8], value: @[13'u8, 14, 15])
  let fixture = namespaceTransitionFixture(decodeOwnedReport(bytes, 2).value, options)
  let key = serviceStorageKey(ServiceIndex(99), [7'u8], ByteLimit(1)).value
  let original = fixture.parent.logicalParentInventory.value.suppliedInventory.value.inventorySource.value.manifestSource.value
  assert original.lookup(key).value.bytes == @[13'u8, 14, 15]
  assert fixture.update.currentUpdateState.lookup(key).value.bytes == value
  let stages = namespaceRefreshStages(fixture)
  assert stages.identities.identityInfo.value.entries == 34 and
      stages.identities.identityInfo.value.keyChecks == 68
  fail(1)
  let info = stages.reconstruction.refreshPlanInfo.value
  assert info.rawKeyBytes == 3 and info.storageBytes == 67 and info.wireBytes == 240 and
      info.bytes >= 67
  var stale = namespaceRefreshLimits
  stale.projection.bytes = ByteLimit(info.bytes-62) # Original three-byte fact cannot authorize the actual65-byte successor copy.
  let refused = planCurrentRefresh(stages.keys, stale)
  assert refused.error == CurrentRefreshPlanError.LimitExceeded and refused.refusedPhase ==
      CurrentRefreshRefusal.Projection
  stale.projection.bytes = ByteLimit(info.bytes)
  assert planCurrentRefresh(stages.keys, stale).error == CurrentRefreshPlanError.None and calls() == 0
  fail(0)
  let logical = executeCurrentLogicalRefresh(stages.complete).value
  let inventory = logical.currentLogicalInventory.value.suppliedInventory.value
  let row = inventory.inventoryServiceAt(InventoryServiceIndex(1)).value
  assert uint32(row.metadata.storageItems) == 8
  assert uint64(row.metadata.storageBytes) == 379'u64+uint64(
      code.len) #317+code bytes originally, then65-3 payload growth.
  assert uint32(row.metadata.lastAccumulation) == 2
  assert sameStateSnapshot(inventory.inventorySource.value.manifestSource.value,
      fixture.update.currentUpdateState)
  fail(1)
  var copied = copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  assert copied[1].storage[1].key == @[7'u8] and copied[1].storage[1].value == value
  copied[1].storage[1].value[0] = 0
  assert copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value[1].storage[1].value == value
  assert original.lookup(key).value.bytes == @[13'u8, 14, 15] and calls() == 0
  fail(0)
  for i in 0..<25: cycle(stages.complete, value)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(stages.complete, value)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_current_refresh_storage", 1000, before, finalBytes)
  echo "state-current-refresh-storage: ok"
try:
  main()
except:
  quit(2) # Actual funded producer writes and full matching are required; detached map edits cannot substitute the genuine successor.
