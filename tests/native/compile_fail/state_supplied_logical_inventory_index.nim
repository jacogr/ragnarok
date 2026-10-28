# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "InventoryServiceIndex", "early": ["copySuppliedStorageKey(", "[2] expected: InventoryServiceIndex but got: InventoryStorageIndex"]}

## A storage child ordinal cannot substitute a service ordinal on supplied raw keys.
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../../src/state/inventory as state_inventory
import ../../../src/codec/bounded as codec_bounded
discard copySuppliedStorageKey(default(SuppliedLogicalInventory), InventoryStorageIndex(0),
    InventoryStorageIndex(0), ByteLimit(1))
