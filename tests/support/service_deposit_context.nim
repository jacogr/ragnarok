# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real complete-source economic fixtures retain independently checked footprint and directory evidence.
import ./[state_inventory_context, account_invariant_context, service_directory_context]
import ../../src/state/[inventory, footprint_audit]
import ../../src/state/service/directory as service_directory
import ../../src/state/account/deposit as account_deposit
import ../../src/codec/state/[accounts as state_accounts, composition as state_composition]
type ServiceDepositTestSource* = object ## Tests retain matching genuine source-bound certificates, never forged owners.
  footprints*: CheckedAccountFootprints
  directory*: StateServiceDirectory
const depositTestSchedule* = AccountDepositSchedule(base: AccountBalance(100), item: AccountBalance(
    2), octet: AccountBalance(3))
proc depositTestSource*(fixture: seq[seq[byte]], services: seq[
    StateService]): ServiceDepositTestSource =
  ## Use existing complete source capture and each bounded factory for every test variant.
  let source = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  ServiceDepositTestSource(footprints: auditAccountFootprints(source,
      invariantFootprintLimits).value,
    directory: buildStateServiceDirectory(source, directoryTestLimits).value)
