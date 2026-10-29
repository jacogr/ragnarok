# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic audit payload/phase guards retain genuine frozen-plan execution as the positive control.
import std/[assertions, cmdline, syncio]
import ../support/[state_inventory_context, account_audit_plan_context]
import ../../src/state/account/audit as account_audit
import ../../src/state/account/audit/plan as account_audit_plan
import ../../src/state/account/invariants as account_invariants
import ../../src/state/inventory
include ./composition_fixture
proc extract(outcome: AccountAuditResult): CheckedAccountInvariants {.noinline.} =
  ## Default or failed execution grants no complete source-bearing certificate.
  outcome.value
proc guardFootprint(outcome: AccountAuditResult) {.noinline.} =
  ## A default result has no failed footprint phase.
  discard outcome.footprintFailure
proc guardLinkage(outcome: AccountAuditResult) {.noinline.} =
  ## A default result has no failed linkage phase.
  discard outcome.linkageFailure
proc guardContent(outcome: AccountAuditResult) {.noinline.} =
  ## A default result has no failed content phase.
  discard outcome.contentFailure
proc guardJoin(outcome: AccountAuditResult) {.noinline.} =
  ## A default result has no failed join phase.
  discard outcome.joinFailure
case paramStr(1)
of "default": discard extract(default(AccountAuditResult)) # No default result.
of "invalid": discard extract(executeAccountAudit(default(
    StateAccountAuditPlan))) # No actual invalid-plan prefix.
of "footprint": guardFootprint(default(AccountAuditResult)) # No invented phase.
of "linkage": guardLinkage(default(AccountAuditResult)) # No invented phase.
of "content": guardContent(default(AccountAuditResult)) # No invented phase.
of "join": guardJoin(default(AccountAuditResult)) # No invented phase.
of "ok":
  let services = inventoryServices()
  let source = captureStateInventory(inventoryManifest(compositionFixture(paramStr(2)), services),
      services, inventoryCaptureLimits).value
  let selected = extract(executeAccountAudit(planAccountAudit(source,
      accountAuditTestLimits).value))
  assert selected.accountInvariantInfo.value.content.bytes == 3
  echo "state-account-audit-execution-results: ok"
else: quit(2) # Unknown selectors cannot satisfy controls.
