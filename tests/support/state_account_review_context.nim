# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real same-source review evidence uses existing bounded factories, never private certificate construction.
import ./state_inventory_context
import ./state_account_audit_plan_context
import ./state_service_directory_context
import ./state_economic_profile_context
import ../../src/chain/parameters as chain_parameters
import ../../src/state/inventory as state_inventory
import ../../src/state/account_audit_plan as state_account_audit_plan
import ../../src/state/account_audit as state_account_audit
import ../../src/state/account_invariants as state_account_invariants
import ../../src/state/service_directory as state_service_directory
import ../../src/state/supervision_table as state_supervision_table
import ../../src/state/economics_table as state_economics_table
import ../../src/state/economic_profile as state_economic_profile
import ../../src/state/footprint_audit as state_footprint_audit
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_composition as codec_state_composition
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
