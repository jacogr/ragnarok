# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedFinalAccumulation", "early": ["applyAccumulationState(", "[2] expected: PreparedFinalAccumulation but got: PreparedAccumulationConsensus"]}

## Only the immutable finalized execution successor authorizes state application.

import ../../../src/state/accumulation_state as state_accumulation_state
import ../../../src/state/accumulation_completion as state_accumulation_completion
import ../../../src/state/store as state_store
import ../../../src/state/accumulation_consensus as state_accumulation_consensus
var target: StateStore
var source: PreparedAccumulationConsensus
discard applyAccumulationState(target, source, default(AccumulationCompositionLimits))
