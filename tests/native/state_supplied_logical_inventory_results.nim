# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict supplied-key guards use complete independent chapters and real manifest capture as positive control.
import std/[assertions, cmdline]
import ../support/[state_inventory_context, supplied_logical_context]
import ../../src/state/supplied/logical_inventory as supplied_logical_inventory
import ../../src/state/[manifest, inventory]
import ../../src/codec/bounded
include ./composition_fixture
proc extract(outcome: SuppliedLogicalResult[SuppliedLogicalInventory]) {.noinline.} =
  ## Failed/default capture exposes no key owner.
  discard outcome.value
proc reason(outcome: SuppliedLogicalResult[SuppliedLogicalInventory]) {.noinline.} =
  ## Only genuine failed compact capture grants its nested reason.
  discard outcome.inventoryFailure
proc source(owner: SuppliedLogicalInventory) {.noinline.} =
  ## Default owners cannot expose compact/source identity.
  discard owner.suppliedInventory.value
proc info(owner: SuppliedLogicalInventory) {.noinline.} =
  ## Default owners cannot expose successful accounting.
  discard owner.suppliedLogicalInfo.value
proc key(outcome: SuppliedLogicalResult[seq[byte]]) {.noinline.} =
  ## Missing indices and refused copies never become empty successful keys.
  discard outcome.value
proc main() {.raises.} =
  ## Fixture construction is restricted to genuine initialized key/error controls.
  case paramStr(1)
  of "default": extract(default(SuppliedLogicalResult[SuppliedLogicalInventory]))
  of "invalid": extract(captureSuppliedLogicalInventory(default(ValidatedStateManifest), [],
      suppliedLogicalTestLimits))
  of "reason": reason(default(SuppliedLogicalResult[SuppliedLogicalInventory]))
  of "source": source(default(SuppliedLogicalInventory))
  of "info": info(default(SuppliedLogicalInventory))
  of "key": key(default(SuppliedLogicalInventory).copySuppliedStorageKey(InventoryServiceIndex(0),
      InventoryStorageIndex(0), ByteLimit(2)))
  of "index", "limit", "ok":
    let services = inventoryServices()
    let manifest = inventoryManifest(compositionFixture(paramStr(2)), services)
    let captured = captureSuppliedLogicalInventory(manifest, services, suppliedLogicalTestLimits)
    let owner = captured.value
    if paramStr(1) == "index":
      key(owner.copySuppliedStorageKey(InventoryServiceIndex(1), InventoryStorageIndex(0),
          ByteLimit(2)))
    elif paramStr(1) == "limit":
      key(owner.copySuppliedStorageKey(InventoryServiceIndex(0), InventoryStorageIndex(0),
          ByteLimit(1)))
    else:
      extract(captured)
      source(owner)
      info(owner)
      key(owner.copySuppliedStorageKey(InventoryServiceIndex(0), InventoryStorageIndex(0),
          ByteLimit(2)))
      echo "state-supplied-logical-inventory-results: ok"
  else: quit(2) # Unknown selector cannot stand in for a guard witness.
try:
  main()
except:
  quit(2) # Setup failure cannot stand in for result contract enforcement.
