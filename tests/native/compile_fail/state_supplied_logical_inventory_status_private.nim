# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Supplied raw-key storage and tagged payloads stay private.
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
var owner = default(SuppliedLogicalResult[SuppliedLogicalInventory])
discard owner.status
