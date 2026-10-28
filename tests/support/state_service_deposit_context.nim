# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real complete-source economic fixtures retain independently checked footprint and directory evidence.
import ./state_inventory_context
import ./codec_account_invariant_context
import ./state_service_directory_context
import ../../src/state/inventory as state_inventory
import ../../src/state/footprint_audit as state_footprint_audit
import ../../src/state/service_directory as state_service_directory
import ../../src/state/account_deposit as state_account_deposit
import ../../src/codec/state_accounts as codec_state_accounts
import ../../src/codec/state_composition as codec_state_composition
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
