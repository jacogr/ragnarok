# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Current chain result representation stays private.
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/state/accumulation_current_chain as state_accumulation_current_chain
import ../../../src/state/accumulation_current_consensus as state_accumulation_current_consensus
import ../../../src/state/store as state_store
var state = default(StateStore)
var view = default(ChainView)
let refused = applyCurrentAccumulationChain(state, view, default(
    PreparedCurrentAccumulationConsensus), ByteLimit(0))
discard refused.status
