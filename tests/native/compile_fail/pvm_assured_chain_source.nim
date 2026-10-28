# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bare composed map cannot replace original assured work in an atomic chain advance.

# @@Verification={"group": "nominal", "expected": "ComposedAssuredState", "early": ["advanceAssuredChain(", "[3] expected: ComposedAssuredState but got: PreparedAccumulationConsensus"]}

import ../../../src/state/assured_chain as state_assured_chain
import ../../../src/state/accumulation_consensus as state_accumulation_consensus
import ../../../src/state/store as state_store
import ../../../src/chain/provider as chain_provider
var state = default(StateStore)
var view = default(ChainView)
discard advanceAssuredChain(state, view, default(PreparedAccumulationConsensus))
