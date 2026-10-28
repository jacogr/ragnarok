# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "data"}

## Compact source storage and result alternatives are private.
import ../../../src/state/inventory as state_inventory
let private = default(StateInventory)
discard private.data
