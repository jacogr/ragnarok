# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bare composed map cannot replace original computed composition authority.

# @@Verification={"group": "nominal", "expected": "ComposedComputedState", "early": ["publishComputedState(", "[2] expected: ComposedComputedState but got: PreparedAccumulationConsensus"]}

import ../../../src/state/computed_state_publication as state_computed_state_publication
import ../../../src/state/accumulation_consensus as state_accumulation_consensus
import ../../../src/state/store as state_store
var target = default(StateStore)
discard publishComputedState(target, default(PreparedAccumulationConsensus))
