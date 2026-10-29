# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bare composed map cannot replace original assured work in an atomic chain advance.

# @@Verification={"group": "nominal", "expected": "ComposedAssuredState", "early": ["advanceAssuredChain(", "[3] expected: ComposedAssuredState but got: PreparedAccumulationConsensus"]}

import ../../../src/state/assured/chain as assured_chain
import ../../../src/state/accumulation/consensus as accumulation_consensus
import ../../../src/state/store
import ../../../src/chain/provider
var state = default(StateStore)
var view = default(ChainView)
discard advanceAssuredChain(state, view, default(PreparedAccumulationConsensus))
