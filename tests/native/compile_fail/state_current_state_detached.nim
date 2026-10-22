# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "CurrentGlobalSerialization", "early": ["qualifyCurrentState(", "[1] expected: CurrentGlobalSerialization but got: ValidatedGlobalState"]}

## Generic global framing cannot replace the original current-bound producer/profile owner.
import ../../../src/state/[current_state, global_snapshot, inventory]
discard qualifyCurrentState(default(ValidatedGlobalState), [], StateInventoryLimits())
