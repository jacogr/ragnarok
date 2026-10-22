# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic guarded audit extraction rejects defaults and preserves a genuine source-bound positive control.
import std/[assertions, cmdline, syncio]
import ../support/state_inventory_context
import ../../src/state/[footprint_audit, inventory]
import ../../src/codec/[bounded, state_accounts]
include composition_fixture
proc extract(outcome: FootprintAuditResult[CheckedAccountFootprints]): CheckedAccountFootprints {.noinline.} =
  ## Prevent static simplification of the guarded complete audit payload.
  outcome.value
proc offender(outcome: FootprintAuditResult[CheckedAccountFootprints]): ServiceIndex {.noinline.} =
  ## Offending accounts exist only for arithmetic or dependent-field failures.
  outcome.failedService
proc location(outcome: FootprintAuditResult[CheckedAccountFootprints]): InventoryServiceIndex {.noinline.} =
  ## No default or resource refusal has an inventory failure coordinate.
  outcome.failedOrdinal
case paramStr(1)
of "default": discard extract(default(FootprintAuditResult[
    CheckedAccountFootprints])) # Default has no certificate.
of "offender": discard offender(default(FootprintAuditResult[
    CheckedAccountFootprints])) # Default has no location.
of "ordinal": discard location(default(FootprintAuditResult[
    CheckedAccountFootprints])) # Default has no coordinate.
of "source":
  let refused = auditAccountFootprints(default(StateInventory), FootprintAuditLimits())
  assert refused.error == FootprintAuditError.InvalidSource
  discard extract(refused) # Invalid input cannot grant an empty success certificate.
of "ok":
  let services = inventoryServices()
  let source = captureStateInventory(inventoryManifest(compositionFixture(paramStr(2)), services),
      services, inventoryCaptureLimits).value
  let checked = extract(auditAccountFootprints(source, FootprintAuditLimits(services: ElementLimit(
      2), checks: ElementLimit(4))))
  assert checked.footprintInfo.value.checks == 4
  echo "state-footprint-audit-results: ok"
else: quit(2) # Unknown selectors cannot impersonate genuine success.
