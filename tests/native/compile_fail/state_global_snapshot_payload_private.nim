# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "completed"}

## Reject forged serialization authority at the actual public boundary.
import ../../../src/state/global_snapshot as state_global_snapshot
let result = default(GlobalStateResult[ValidatedGlobalState])
discard result.completed
