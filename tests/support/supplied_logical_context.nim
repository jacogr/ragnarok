# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit independent budgets for compact facts and extra retained supplied raw-key arrays.
import ./state_inventory_context
import ../../src/state/supplied/logical_inventory as supplied_logical_inventory
import ../../src/codec/bounded
const suppliedLogicalTestLimits* = SuppliedLogicalLimits(inventory: inventoryCaptureLimits,
    keys: ElementLimit(64), rawKeyBytes: ByteLimit(4096), bytes: ByteLimit(65536))
