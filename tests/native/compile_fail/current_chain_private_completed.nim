# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Current chain result representation stays private.
import ../../../src/chain/provider
import ../../../src/codec/bounded
import ../../../src/state/accumulation/current/[chain as accumulation_current_chain,
    consensus as accumulation_current_consensus]
import ../../../src/state/store
var state = default(StateStore)
var view = default(ChainView)
let refused = applyCurrentAccumulationChain(state, view, default(
    PreparedCurrentAccumulationConsensus), ByteLimit(0))
discard refused.completed
