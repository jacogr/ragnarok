# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "CurrentStateSerialization", "early": ["captureCurrentLogicalState(", "[1] expected: CurrentStateSerialization but got: SuppliedLogicalInventory"]}

## A detached raw-key owner cannot substitute original authenticated current/profile provenance.
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
discard captureCurrentLogicalState(default(SuppliedLogicalInventory), [], SuppliedLogicalLimits())
