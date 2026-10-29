# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real same-source review evidence uses existing bounded factories, never private certificate construction.
import ./[state_inventory_context, account_audit_plan_context, service_directory_context, economic_profile_context]
import ../../src/chain/parameters
import ../../src/state/inventory
import ../../src/state/account/audit/plan as account_audit_plan
import ../../src/state/account/[audit as account_audit, invariants as account_invariants]
import ../../src/state/service/directory as service_directory
import ../../src/state/[supervision_table, economics_table, economic_profile, footprint_audit]
import ../../src/codec/bounded
import ../../src/codec/state/composition as state_composition
type AccountReviewTestEvidence* = object ## Test-owned public factory outputs share one genuine complete inventory.
  invariants*: CheckedAccountInvariants
  supervision*: StateSupervisionTable
  economics*: StateEconomicsTable
proc accountReviewEvidence*(fixture: seq[seq[byte]], services: seq[
    StateService]): AccountReviewTestEvidence =
  ## Preserve exact owner identity through all independently bounded predicate and observation factories.
  let source = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  let invariants = executeAccountAudit(planAccountAudit(source, accountAuditTestLimits).value).value
  let directory = buildStateServiceDirectory(source, directoryTestLimits).value
  let footprints = auditAccountFootprints(source, accountAuditTestLimits.footprints).value
  let profile = captureEconomicProfile(decodeParameters(economicTestWire()).value).value
  AccountReviewTestEvidence(invariants: invariants,
    supervision: buildSupervisionTable(directory, SupervisionTableLimits(services: ElementLimit(2),
        bytes: ByteLimit(4096))).value,
    economics: buildEconomicsTable(footprints, directory, profile, EconomicsTableLimits(
        services: ElementLimit(2), bytes: ByteLimit(4096))).value)
