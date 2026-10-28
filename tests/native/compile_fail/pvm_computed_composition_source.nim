# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bare final-state plan cannot replace original computed finalization authority.

# @@Verification={"group": "nominal", "expected": "FinalizedComputedAccumulation", "early": ["composeComputedState(", "[1] expected: FinalizedComputedAccumulation but got: PreparedFinalAccumulation"]}

import ../../../src/state/computed_composition as state_computed_composition
import ../../../src/state/accumulation_completion as state_accumulation_completion
import ../../../src/state/accumulation_finalization as state_accumulation_finalization
discard composeComputedState(default(PreparedFinalAccumulation), AccumulationCompositionLimits())
