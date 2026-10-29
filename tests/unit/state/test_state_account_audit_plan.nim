# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen whole-account policies preflight complete work while granting no successful semantic invariants.
# @@Verification={"arc": "state_account_audit_plan_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[state_inventory_context, account_audit_plan_context, arc_evidence]
import ../../../src/state/account/audit/plan as account_audit_plan
import ../../../src/state/inventory
import ../../../src/codec/bounded
include ../../native/composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse hashes after real complete source capture.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Planning must never hash or copy a preimage payload.
proc expect(source: StateInventory, limits: AccountAuditLimits, phase: AccountAuditRefusal) =
  ## Check both bounded refusal and its exact guarded policy boundary.
  let refused = planAccountAudit(source, limits)
  assert refused.error == AccountAuditPlanError.LimitExceeded and refused.refusedPhase == phase
proc cycle(source: StateInventory) =
  ## Retire a fixed frozen plan and retained source handle each cycle.
  assert planAccountAudit(source, accountAuditTestLimits).value.accountPlanInfo.value.planningChecks == 5
proc main() {.raises.} =
  ## Capture complete valid and wrong-content sources before disabling all hashing.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  let source = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  services[0].preimages[0].value[0] = 98
  let wrong = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  services = @[]
  let empty = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  fail(1)
  var limits = accountAuditTestLimits
  let result = planAccountAudit(source, limits)
  assert result.error == AccountAuditPlanError.None
  let plan = result.value
  let info = plan.accountPlanInfo.value
  assert info.services == 2 and info.planningChecks == 5 and info.footprintChecks == 4
  assert info.preimages == 1 and info.contentBytes == 3 and info.comparisonCeiling == 1
  assert sameStateInventory(plan.accountPlanInventory.value, source)
  limits.planning = ElementLimit(4)
  expect(source, limits, AccountAuditRefusal.Planning)
  assert uint64(plan.accountPlanLimits.value.planning) == 5
  limits = accountAuditTestLimits
  limits.footprints.checks = ElementLimit(3)
  expect(source, limits, AccountAuditRefusal.Footprints)
  limits = accountAuditTestLimits
  limits.content.preimages = ElementLimit(0)
  expect(source, limits, AccountAuditRefusal.Content)
  limits = accountAuditTestLimits
  limits.content.totalBytes = ByteLimit(2)
  expect(source, limits, AccountAuditRefusal.Content)
  limits = accountAuditTestLimits
  limits.content.perValue = ByteLimit(2)
  expect(source, limits, AccountAuditRefusal.Content)
  limits = accountAuditTestLimits
  limits.linkage.preimages = ElementLimit(0)
  expect(source, limits, AccountAuditRefusal.Linkage)
  limits = accountAuditTestLimits
  limits.linkage.comparisons = ElementLimit(0)
  expect(source, limits, AccountAuditRefusal.Linkage)
  limits = accountAuditTestLimits
  limits.footprints.services = ElementLimit(1)
  expect(source, limits, AccountAuditRefusal.Footprints)
  limits = accountAuditTestLimits
  limits.content.services = ElementLimit(1)
  expect(source, limits, AccountAuditRefusal.Content)
  limits = accountAuditTestLimits
  limits.linkage.services = ElementLimit(1)
  expect(source, limits, AccountAuditRefusal.Linkage)
  var copied = plan.accountPlanLimits.value
  copied.content.totalBytes = ByteLimit(0)
  assert uint64(plan.accountPlanLimits.value.content.totalBytes) == 3
  assert planAccountAudit(wrong, accountAuditTestLimits).error == AccountAuditPlanError.None
  assert planAccountAudit(empty, AccountAuditLimits()).value.accountPlanInfo.value.planningChecks == 0
  assert planAccountAudit(default(StateInventory), accountAuditTestLimits).error ==
      AccountAuditPlanError.InvalidSource
  assert default(StateAccountAuditPlan).accountPlanInfo.error == AccountAuditPlanError.Uninitialized
  assert default(StateAccountAuditPlan).accountPlanInventory.error ==
      AccountAuditPlanError.Uninitialized
  assert default(StateAccountAuditPlan).accountPlanLimits.error ==
      AccountAuditPlanError.Uninitialized
  assert calls() == 0
  for i in 0..<25: cycle(source) # Warm fixed-plan retained-source extraction.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source) # No plan or source handle accumulates after retirement.
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_account_audit_plan", 1000, before, finalBytes)
  fail(0)
  echo "state-account-audit-plan: ok"
try:
  main()
except:
  quit(2) # Setup failure never qualifies planning or source lifetime evidence.
