# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private computed stopped/final-state authority or result selection.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/computed/finalization as computed_finalization
var candidate: ComputedFinalizationResult[FinalizedComputedAccumulation]
discard candidate.completed
