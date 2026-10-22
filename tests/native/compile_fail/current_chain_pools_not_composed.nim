# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationConsensus but got: PreparedCurrentAccumulationAuthorization"}

## Current composed ownership is required before joint state/view installation.
import ../../../src/chain/provider
import ../../../src/codec/bounded
import ../../../src/state/[accumulation_current_chain, accumulation_current_authorization, store]
var state = default(StateStore)
var view = default(ChainView)
discard applyCurrentAccumulationChain(state, view, default(
    PreparedCurrentAccumulationAuthorization), ByteLimit(0))
