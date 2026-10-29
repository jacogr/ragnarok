# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Configured/completed frozen plans and final logical owners retain actual source graphs after every constructing fixture/key/temporary scope retires.
# @@Verification={"arc":"state_current_logical_scope_lifetime_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_repeated_logical_context, current_namespace_refresh_context,
    supplied_services_context, arc_evidence]
import ../../../src/state/current/logical/refresh as current_logical_refresh
import ../../../src/state/current/refresh/plan as current_refresh_plan
import ../../../src/state/current/[request_keys as current_request_keys,
    identities as current_identities, logical as current_logical, state as current_state,
    globals as current_globals, profile as current_profile]
import ../../../src/state/supplied/[logical_inventory as supplied_logical_inventory,
    services as supplied_services]
import ../../../src/state/[inventory, manifest, store]
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/codec/[bounded, report_owned]
proc planOnly(base: OwnedReport, completed: bool): CurrentLogicalRefreshPlan =
  ## All genuine signatures, original fixtures, full prior results and temporary stage records are local; only the frozen plan may escape.
  let fixture = repeatedLogicalFixture(base)
  if completed:
    return namespaceRefreshStages(fixture.logical, fixture.next).complete
  namespaceRefreshStages(fixture.first).complete
proc keysOnly(base: OwnedReport, completed: bool): CurrentRequestKeys =
  ## Dropping the local full plan must not invalidate the immutable cached request/original/actual-target graph it projected.
  let plan = planOnly(base, completed)
  plan.logicalRefreshPlanSource.value.refreshPlanSource.value
proc logicalOnly(base: OwnedReport, completed: bool): CurrentLogicalState =
  ## No constructing plan, original logical parent or temporary service reconstruction remains live after this real successful return.
  let plan = planOnly(base, completed)
  executeCurrentLogicalRefresh(plan).value
proc verify(logical: CurrentLogicalState, slot: uint32) =
  ## Final current/global/profile/raw-key owners retain only valid actual original producer handles and complete namespace payloads.
  let inventory = logical.currentLogicalInventory.value.suppliedInventory.value
  let producer = logical.currentLogicalSource.value.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedUpdate.value
  assert producer.currentUpdateChildContext.slot == slot
  assert sameStateSnapshot(inventory.inventorySource.value.manifestSource.value,
      producer.currentUpdateState)
  for i in 0..<2:
    let service = inventory.inventoryServiceAt(InventoryServiceIndex(uint64(i))).value
    assert uint32(service.metadata.lastAccumulation) == slot and service.preimages == 3 and
        service.requests == 3
  let detached = copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  assert detached[0].storage[1].key.len == 2 and detached[0].preimages[1].value.len == 3
  assert detached[1].storage[0].key.len == 0 and detached[1].preimages[0].value.len == 0
proc cycle(first, second: CurrentLogicalRefreshPlan, configured, current: CurrentLogicalState) =
  ## Retire fresh returned captures/copies while independently escaped final owners remain usable after their original scopes are gone.
  verify(executeCurrentLogicalRefresh(first).value, 2)
  verify(executeCurrentLogicalRefresh(second).value, 3)
  verify(configured, 2)
  verify(current, 3)
proc main() {.raises.} =
  ## The only common caller input is immutable report bytes; it retains no parent/state/view or logical namespace graph.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let first = planOnly(base, false)
  let second = planOnly(base, true)
  let configured = logicalOnly(base, false)
  let current = logicalOnly(base, true)
  verify(configured, 2)
  verify(current, 3)
  let keys = keysOnly(base, true)
  let reconstruction = planCurrentRefresh(keys, namespaceRefreshLimits).value
  let rebuilt = planCurrentLogicalRefresh(reconstruction, namespaceLogicalLimits()).value
  verify(executeCurrentLogicalRefresh(rebuilt).value, 3)
  assert keys.requestKeysSource.value.identityParent.error == CurrentIdentityError.WrongSource
  for i in 0..<25: cycle(first, second, configured, current)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(first, second, configured, current)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_current_logical_scope_lifetime", 1000, before, finalBytes)
  echo "state-current-logical-scope-lifetime: ok"
try:
  main()
except:
  quit(2) # Retired constructing scopes cannot be silently replaced by another surviving fixture or caller-owned map.
