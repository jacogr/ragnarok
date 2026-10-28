# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic supervision payload guards preserve genuine complete-source selection as a positive control.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_inventory_context
import ../support/state_service_directory_context
import ../../src/state/service_supervision as state_service_supervision
import ../../src/state/service_directory as state_service_directory
import ../../src/state/inventory as state_inventory
import ../../src/codec/state_accounts as codec_state_accounts
include nimony_composition_fixture
proc extract(outcome: ServiceSupervisionResult[ServiceSupervision]): ServiceSupervision {.noinline.} =
  ## Default or failed target queries cannot expose source-bearing authority.
  outcome.value
case paramStr(1)
of "default": discard extract(default(ServiceSupervisionResult[ServiceSupervision])) # No default source.
of "invalid": discard extract(resolveServiceSupervision(default(StateServiceDirectory),
    ServiceIndex(7))) # No default directory authority.
of "ok":
  let services = inventoryServices()
  let source = captureStateInventory(inventoryManifest(compositionFixture(paramStr(2)), services),
      services, inventoryCaptureLimits).value
  let directory = buildStateServiceDirectory(source, directoryTestLimits).value
  let selected = extract(resolveServiceSupervision(directory, ServiceIndex(8)))
  assert uint32(selected.supervisionInfo.value.effective) == 7
  echo "state-service-supervision-results: ok"
else: quit(2) # Unknown selectors cannot pass controls.
