# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic frozen-plan payload/policy guards retain a genuine complete-source positive control.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_inventory_context
import ../support/state_account_audit_plan_context
import ../../src/state/account_audit_plan as state_account_audit_plan
import ../../src/state/inventory as state_inventory
include nimony_composition_fixture
proc extract(outcome: AccountAuditPlanResult[StateAccountAuditPlan]): StateAccountAuditPlan {.noinline.} =
  ## No default or source refusal grants frozen executable policy.
  outcome.value
proc phase(outcome: AccountAuditPlanResult[StateAccountAuditPlan]) {.noinline.} =
  ## Defaults and invalid sources invent no resource boundary.
  discard outcome.refusedPhase
case paramStr(1)
of "default": discard extract(default(AccountAuditPlanResult[StateAccountAuditPlan])) # No default plan.
of "phase": phase(default(AccountAuditPlanResult[StateAccountAuditPlan])) # No default refusal boundary.
of "invalid": discard extract(planAccountAudit(default(StateInventory),
    accountAuditTestLimits)) # Actual source refusal.
of "ok":
  let services = inventoryServices()
  let source = captureStateInventory(inventoryManifest(compositionFixture(paramStr(2)), services),
      services, inventoryCaptureLimits).value
  let plan = extract(planAccountAudit(source, accountAuditTestLimits))
  assert plan.accountPlanInfo.value.planningChecks == 5
  echo "state-account-audit-plan-results: ok"
else: quit(2) # Unknown selectors cannot satisfy controls.
