# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "SuppliedLogicalInventory", "early": ["copySuppliedServices(", "[1] expected: SuppliedLogicalInventory but got: StateInventory"]}

## Compact hashed facts cannot reconstruct missing raw-key provenance.
import ../../../src/state/supplied_services as state_supplied_services
import ../../../src/state/inventory as state_inventory
discard copySuppliedServices(default(StateInventory), SuppliedServicesLimits())
