# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bare final-state plan cannot replace original computed finalization authority.

# @@Verification={"group": "nominal", "expected": "FinalizedComputedAccumulation", "early": ["composeComputedState(", "[1] expected: FinalizedComputedAccumulation but got: PreparedFinalAccumulation"]}

import ../../../src/state/computed/composition as computed_composition
import ../../../src/state/accumulation/[completion as accumulation_completion,
    finalization as accumulation_finalization]
discard composeComputedState(default(PreparedFinalAccumulation), AccumulationCompositionLimits())
