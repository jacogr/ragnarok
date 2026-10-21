# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private computed stopped/final-state authority or result selection.

# @@Verification={"group": "privacy", "expected": "finalizationReason"}

import ../../../src/state/computed_finalization
var candidate: ComputedFinalizationResult[FinalizedComputedAccumulation]
discard candidate.finalizationReason
