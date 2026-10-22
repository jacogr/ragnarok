# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "InventoryStorageIndex", "early": ["inventoryStorageAt(", "[3] expected: InventoryStorageIndex but got: InventoryPreimageIndex"]}

## Nominal coordinates and partial evidence cannot impersonate compact source authority.
import ../../../src/state/inventory
discard inventoryStorageAt(default(StateInventory), InventoryServiceIndex(0),
    InventoryPreimageIndex(0))
