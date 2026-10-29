# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic directory payload guards retain genuine complete-source lookup as the positive control.
import std/[assertions, cmdline, syncio]
import ../support/state_inventory_context
import ../../src/state/service/directory as service_directory
import ../../src/state/inventory
import ../../src/codec/bounded
import ../../src/codec/state/accounts as state_accounts
include ./composition_fixture
proc extract(outcome: ServiceDirectoryResult[StateServiceDirectory]): StateServiceDirectory {.noinline.} =
  ## Default and failed directory construction have no source-bearing success.
  outcome.value
proc coordinate(outcome: ServiceDirectoryResult[InventoryServiceIndex]): InventoryServiceIndex {.noinline.} =
  ## Missing or default service queries have no invented original ordinal.
  outcome.value
case paramStr(1)
of "default": discard extract(default(ServiceDirectoryResult[StateServiceDirectory])) # No default directory.
of "invalid": discard extract(buildStateServiceDirectory(default(StateInventory),
    ServiceDirectoryLimits())) # Actual source refusal.
of "lookup": discard coordinate(default(StateServiceDirectory).findService(ServiceIndex(
    7))) # Uninitialized is not absence.
of "ok":
  let services = inventoryServices()
  let source = captureStateInventory(inventoryManifest(compositionFixture(paramStr(2)), services),
      services, inventoryCaptureLimits).value
  let directory = extract(buildStateServiceDirectory(source, ServiceDirectoryLimits(
      services: ElementLimit(2), comparisons: ElementLimit(1), bytes: ByteLimit(4096))))
  assert uint64(coordinate(directory.findService(ServiceIndex(7)))) == 0
  echo "state-service-directory-results: ok"
else: quit(2) # Unknown modes cannot satisfy positive controls.
