# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual collected supplied qualification supports caller-owned complete declarations and refuses stale, mutated, resource and backend inputs.
# @@Verification={"arc":"application_collected_supplied_state_arc_release"}
import std/assertions
import std/syncio
import ../../support/app_collected_native_context
import ../../support/app_collected_supplied_context
import ../../support/testing_arc_evidence
import ../../../src/app/collected_supplied_plan as app_collected_supplied_plan
import ../../../src/app/collected_supplied_state as app_collected_supplied_state
import ../../../src/app/chain as app_chain
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/current_state as state_current_state
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../../src/state/inventory as state_inventory
import ../../../src/state/manifest as state_manifest
import ../../../src/state/store as state_store
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/codec/bounded as codec_bounded
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Fail actual complete matching only after original plan and genuine worker collection are finished.
proc cycle(fixture: CollectedNativeFixture, plan: CollectedSuppliedPlan) =
  ## Retire each new pair of compact inventories and raw-key owners without changing the canonical parent.
  let result = executeCollectedSupplied(fixture.chain, plan, fixture.declarations)
  assert result.error == CollectedSuppliedError.None
proc main() {.raises.} =
  ## The genuine target and explicit known namespaces are independent inputs that must reproduce the whole actual map.
  let fixture = collectedNativeFixture()
  let plan = suppliedNativePlan(fixture)
  let result = executeCollectedSupplied(fixture.chain, plan, fixture.declarations)
  assert result.error == CollectedSuppliedError.None
  let state = result.value.currentLogicalSource.value
  let raw = result.value.currentLogicalInventory.value.suppliedInventory.value
  assert not sameStateInventory(raw, state.currentStateInventory.value)
  assert sameStateSnapshot(raw.inventorySource.value.manifestSource.value,
      plan.collectedSuppliedUpdate.value.currentUpdateState)
  var changed = fixture.declarations
  changed[0].storage[0].key.add(222'u8)
  assert executeCollectedSupplied(fixture.chain, plan, changed).error ==
      CollectedSuppliedError.StateFailure
  let empty = default(CollectedSuppliedPlan)
  assert executeCollectedSupplied(fixture.chain, empty, fixture.declarations).error ==
      CollectedSuppliedError.InvalidPlan
  var limits = collectedSuppliedTestLimits()
  limits.logical.keys = ElementLimit(0)
  let short = planCollectedSupplied(fixture.chain, fixture.receipt, limits).value
  assert executeCollectedSupplied(fixture.chain, short, fixture.declarations).error ==
      CollectedSuppliedError.LogicalFailure
  fail(1)
  assert executeCollectedSupplied(fixture.chain, plan, fixture.declarations).error ==
      CollectedSuppliedError.StateFailure
  fail(0)
  var adopted = fixture.chain
  adopted.installPrepared(plan.collectedSuppliedUpdate.value)
  assert executeCollectedSupplied(adopted, plan, fixture.declarations).error ==
      CollectedSuppliedError.StaleUpdate
  for i in 0..<25: cycle(fixture, plan)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(fixture, plan)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("app_collected_supplied_state", 1000, before, after)
  echo "application-collected-supplied-state: ok"
try:
  main()
except:
  quit(2) # No ordinary setup failure can supply complete current logical evidence.
