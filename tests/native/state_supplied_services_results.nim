# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict detached projection guards use a genuine captured complete logical source as positive control.
import std/[assertions, cmdline]
import ../support/[state_inventory_context, supplied_logical_context, supplied_services_context]
import ../../src/state/supplied/[services as supplied_services,
    logical_inventory as supplied_logical_inventory]
include ./composition_fixture
proc extract(outcome: SuppliedServicesResult) {.noinline.} =
  ## Failed/default projection never becomes an empty successful declaration sequence.
  discard outcome.value
proc main() {.raises.} =
  ## Complete source construction occurs only for positive control and actual short-budget witness.
  case paramStr(1)
  of "default": extract(default(SuppliedServicesResult))
  of "invalid": extract(copySuppliedServices(default(SuppliedLogicalInventory),
      suppliedServicesTestLimits))
  of "ok":
    let services = inventoryServices()
    let manifest = inventoryManifest(compositionFixture(paramStr(2)), services)
    let owner = captureSuppliedLogicalInventory(manifest, services, suppliedLogicalTestLimits).value
    let copied = copySuppliedServices(owner, suppliedServicesTestLimits)
    extract(copied)
    assert copied.value[0].storage[0].key == @[byte(1), 2]
    echo "state-supplied-services-results: ok"
  else: quit(2) # Unknown selector cannot qualify guards.
try:
  main()
except:
  quit(2) # Setup failure cannot replace contract evidence.
