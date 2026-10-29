# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "CurrentStateSerialization", "early": ["captureCurrentLogicalState(", "[1] expected: CurrentStateSerialization but got: SuppliedLogicalInventory"]}

## A detached raw-key owner cannot substitute original authenticated current/profile provenance.
import ../../../src/state/current/logical as current_logical
import ../../../src/state/supplied/logical_inventory as supplied_logical_inventory
discard captureCurrentLogicalState(default(SuppliedLogicalInventory), [], SuppliedLogicalLimits())
