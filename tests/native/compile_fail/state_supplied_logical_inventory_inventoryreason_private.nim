# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "inventoryReason"}

## Supplied raw-key storage and tagged payloads stay private.
import ../../../src/state/supplied/logical_inventory as supplied_logical_inventory
var owner = default(SuppliedLogicalResult[SuppliedLogicalInventory])
discard owner.inventoryReason
