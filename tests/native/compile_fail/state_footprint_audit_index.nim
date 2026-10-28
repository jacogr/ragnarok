# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "InventoryServiceIndex", "early": ["checkedFootprintAt(", "[2] expected: InventoryServiceIndex but got: InventoryStorageIndex"]}

## Storage ordinals cannot select service certificates.
import ../../../src/state/footprint_audit as state_footprint_audit
import ../../../src/state/inventory as state_inventory
discard checkedFootprintAt(default(CheckedAccountFootprints), InventoryStorageIndex(0))
