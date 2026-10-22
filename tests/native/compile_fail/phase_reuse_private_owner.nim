# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Caller code cannot forge reusable account coverage or map ownership.
import ../../../src/state/accumulation_account_phase
let phase = default(PreparedAccumulationAccountPhase)
discard phase.data
