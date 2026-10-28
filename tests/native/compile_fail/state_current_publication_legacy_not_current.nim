# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationConsensus but got: PreparedAccumulationConsensus", "early": ["publishCurrentAccumulationState(", "[2] expected: PreparedCurrentAccumulationConsensus but got: PreparedAccumulationConsensus"]}

## Exact current consensus composition is required before publication.
import ../../../src/state/accumulation_current_publication as state_accumulation_current_publication
import ../../../src/state/accumulation_consensus as state_accumulation_consensus
import ../../../src/state/store as state_store
var state = default(StateStore)
discard publishCurrentAccumulationState(state, default(PreparedAccumulationConsensus))
