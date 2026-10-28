# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "CurrentGlobalSerialization", "early": ["qualifyCurrentState(", "[1] expected: CurrentGlobalSerialization but got: ValidatedGlobalState"]}

## Generic global framing cannot replace the original current-bound producer/profile owner.
import ../../../src/state/current_state as state_current_state
import ../../../src/state/global_snapshot as state_global_snapshot
import ../../../src/state/inventory as state_inventory
discard qualifyCurrentState(default(ValidatedGlobalState), [], StateInventoryLimits())
