# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Caller code cannot replace statistics rows or their terminal source.
import ../../../src/state/accumulation_current_statistics
let owner = default(PreparedCurrentAccumulationStatistics)
discard owner.data
