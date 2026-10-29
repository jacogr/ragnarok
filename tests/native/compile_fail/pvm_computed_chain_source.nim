# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bare composed map cannot replace original computed work in an atomic chain advance.

# @@Verification={"group": "nominal", "expected": "ComposedComputedState", "early": ["advanceComputedChain(", "[3] expected: ComposedComputedState but got: PreparedAccumulationConsensus"]}

import ../../../src/state/computed/chain as computed_chain
import ../../../src/state/accumulation/consensus as accumulation_consensus
import ../../../src/state/store
import ../../../src/chain/provider
var state = default(StateStore)
var view = default(ChainView)
discard advanceComputedChain(state, view, default(PreparedAccumulationConsensus))
