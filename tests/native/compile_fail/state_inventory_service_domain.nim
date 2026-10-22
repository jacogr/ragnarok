# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "InventoryServiceIndex", "early": ["inventoryServiceAt(", "[2] expected: InventoryServiceIndex but got: ServiceIndex"]}

## Nominal coordinates and partial evidence cannot impersonate compact source authority.
import ../../../src/state/inventory
import ../../../src/codec/composite
discard inventoryServiceAt(default(StateInventory), ServiceIndex(0))
