# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group":"nominal","expected":"PreparedFinalAccumulation","early":["applyAccumulationChain(","[3] expected: PreparedFinalAccumulation but got: StateStoreSnapshot"]}

## Raw state maps cannot stand in for the finalized execution authority.

import ../../../src/state/accumulation_chain as state_accumulation_chain
import ../../../src/state/accumulation_completion as state_accumulation_completion
import ../../../src/state/store as state_store
import ../../../src/chain/provider as chain_provider
var state = default(StateStore)
var view = default(ChainView)
discard applyAccumulationChain(state, view, default(StateStoreSnapshot), default(AccumulationCompositionLimits))
