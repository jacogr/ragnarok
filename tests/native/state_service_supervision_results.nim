# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic supervision payload guards preserve genuine complete-source selection as a positive control.
import std/[assertions, cmdline, syncio]
import ../support/[state_inventory_context, service_directory_context]
import ../../src/state/[service_supervision, service_directory, inventory]
import ../../src/codec/state_accounts
include composition_fixture
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
