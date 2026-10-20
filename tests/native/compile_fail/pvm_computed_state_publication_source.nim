# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bare composed map cannot replace original computed composition authority.

# @@Verification={"group": "nominal", "expected": "ComposedComputedState", "early": ["publishComputedState(", "[2] expected: ComposedComputedState but got: PreparedAccumulationConsensus"]}

import ../../../src/state/[computed_state_publication, accumulation_consensus, store]
var target = default(StateStore)
discard publishComputedState(target, default(PreparedAccumulationConsensus))
