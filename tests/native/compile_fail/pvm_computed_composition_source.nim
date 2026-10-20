# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bare final-state plan cannot replace original computed finalization authority.

# @@Verification={"group": "nominal", "expected": "FinalizedComputedAccumulation", "early": ["composeComputedState(", "[1] expected: FinalizedComputedAccumulation but got: PreparedFinalAccumulation"]}

import ../../../src/state/[computed_composition, accumulation_completion, accumulation_finalization]
discard composeComputedState(default(PreparedFinalAccumulation), AccumulationCompositionLimits())
