# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group":"nominal","expected":"PreparedFinalAccumulation","early":["applyAccumulationChain(","[3] expected: PreparedFinalAccumulation but got: StateStoreSnapshot"]}

## Raw state maps cannot stand in for the finalized execution authority.

import ../../../src/state/[accumulation_chain, accumulation_completion, store]
import ../../../src/chain/provider
var state = default(StateStore)
var view = default(ChainView)
discard applyAccumulationChain(state, view, default(StateStoreSnapshot), default(AccumulationCompositionLimits))
