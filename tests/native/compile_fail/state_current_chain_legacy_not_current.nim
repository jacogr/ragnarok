# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationConsensus but got: PreparedAccumulationConsensus", "early": ["applyCurrentAccumulationChain(", "[3] expected: PreparedCurrentAccumulationConsensus but got: PreparedAccumulationConsensus"]}

## Current composed ownership is required before joint state/view installation.
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/state/accumulation_current_chain as state_accumulation_current_chain
import ../../../src/state/accumulation_consensus as state_accumulation_consensus
import ../../../src/state/store as state_store
var state = default(StateStore)
var view = default(ChainView)
discard applyCurrentAccumulationChain(state, view, default(PreparedAccumulationConsensus),
    ByteLimit(0))
