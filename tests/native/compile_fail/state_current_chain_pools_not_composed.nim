# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationConsensus but got: PreparedCurrentAccumulationAuthorization", "early": ["applyCurrentAccumulationChain(", "[3] expected: PreparedCurrentAccumulationConsensus but got: PreparedCurrentAccumulationAuthorization"]}

## Current composed ownership is required before joint state/view installation.
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/state/accumulation_current_chain as state_accumulation_current_chain
import ../../../src/state/accumulation_current_authorization as state_accumulation_current_authorization
import ../../../src/state/store as state_store
var state = default(StateStore)
var view = default(ChainView)
discard applyCurrentAccumulationChain(state, view, default(
    PreparedCurrentAccumulationAuthorization), ByteLimit(0))
