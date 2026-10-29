# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Nonempty reordered service/child declarations remain original-owned after caller mutation and through genuine configured/completed current refresh.
# @@Verification={"arc":"state_current_logical_permuted_inputs_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_namespace_transition_context, current_namespace_execution_context,
    current_namespace_context, current_namespace_refresh_context, current_repeated_logical_context,
    current_identity_context, supplied_logical_context, supplied_services_context,
    accumulation_execution_context, arc_evidence]
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
    requests as state_requests]
proc cycle(plan: CurrentLogicalRefreshPlan, value, code: openArray[byte]) =
  ## Retire fresh complete captures/projections while original supplied ordinals remain tied to their actual service/hash/key identities.
  let logical = executeCurrentLogicalRefresh(plan).value
  let rows = copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  assert uint32(rows[0].service) == 99 and uint32(rows[1].service) == 42
  assert rows[0].storage[0].key == @[7'u8] and rows[0].storage[0].value.len == value.len
  assert rows[0].preimages[0].value.len == code.len
  for i in 0..<value.len: assert rows[0].storage[0].value[i] == value[
      i] # Actual target growth follows identity, not canonical service/child ordinal assumptions.
  for i in 0..<code.len: assert rows[0].preimages[0].value[i] == code[i]
proc main() {.raises.} =
  ## The actual funded guest changes only its original storage value; all mutable logical declarations are independently reordered before capture.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let value = @[21'u8, 22, 23, 24, 25]
  let code = namespaceStorageCode(value)
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondProgram = code
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  options.signed.serviceNamespaces[1].storage[1] = StateStorageItem(key: @[7'u8], value: @[13'u8, 14, 15])
  let fixture = namespaceTransitionFixture(decodeOwnedReport(bytes, 2).value, options)
  var declarations = @[fixture.services[1], fixture.services[0]]
  for i in 0..<2:
    declarations[i].storage = @[declarations[i].storage[1], declarations[i].storage[0]]
    declarations[i].preimages = @[declarations[i].preimages[2], declarations[i].preimages[1],
        declarations[i].preimages[0]]
    declarations[i].requests = @[declarations[i].requests[2], declarations[i].requests[1],
        declarations[i].requests[0]]
  let parent = captureLogicalParent(fixture.parent.logicalParentGlobals.value, declarations,
      suppliedLogicalTestLimits).value
  for i in 0..<2:
    declarations[i].metadata.storageItems = AccountStorageItems(0)
    declarations[i].storage[0].key[0] = 200
    declarations[i].preimages[0].value[0] = 255
    declarations[i].requests[0].history = requestedHistory() # Caller owns these arrays again after synchronous capture; no retained borrow may follow these changes.
  let retained = parent.logicalParentInventory.value
  assert retained.copySuppliedStorageKey(InventoryServiceIndex(0), InventoryStorageIndex(0),
      ByteLimit(1)).value == @[7'u8]
  let preserved = preserveCurrentIdentities(parent, fixture.update, currentIdentityTestLimits).value
  let keys = captureCurrentRequestKeys(preserved, namespaceRequestLimits).value
  let reconstruction = planCurrentRefresh(keys, namespaceRefreshLimits).value
  let first = executeCurrentLogicalRefresh(planCurrentLogicalRefresh(reconstruction,
      namespaceLogicalLimits()).value).value
  let actual = copySuppliedServices(first.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  assert uint32(actual[0].service) == 99 and actual[0].storage[0].key == @[7'u8] and actual[
      0].storage[0].value == value
  assert actual[0].preimages[0].value == code and actual[0].requests[0].history.state ==
      RequestState.Available
  assert uint32(actual[0].metadata.storageItems) == 8
  assert sameStateSnapshot(first.currentLogicalInventory.value.suppliedInventory.value.inventorySource.value.manifestSource.value,
      fixture.update.currentUpdateState)
  let next = nextLogicalEmpty(fixture.update)
  let stages = namespaceRefreshStages(first, next)
  let repeated = executeCurrentLogicalRefresh(stages.complete).value
  let row = repeated.currentLogicalInventory.value.suppliedInventory.value.inventoryServiceAt(
      InventoryServiceIndex(0)).value
  assert uint32(row.service) == 99 and uint32(row.metadata.lastAccumulation) == 3
  for i in 0..<25: cycle(stages.complete, value, code)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(stages.complete, value, code)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_current_logical_permuted_inputs", 1000, before, finalBytes)
  echo "state-current-logical-permuted-inputs: ok"
try:
  main()
except:
  quit(2) # Reordered/mutated supplied declarations never substitute an authenticated immutable original or actual target owner.
