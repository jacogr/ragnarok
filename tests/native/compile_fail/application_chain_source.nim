# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group":"nominal","expected":"PreparedFinalAccumulation","early":["applyAccumulation(","[2] expected: PreparedFinalAccumulation but got: StateStoreSnapshot"]}

## The canonical application boundary cannot treat a detached map as finalized execution authority.

import ../../../src/app/chain
import ../../../src/state/[store, accumulation_completion]
var owner = default(ApplicationChain)
discard applyAccumulation(owner, default(StateStoreSnapshot), default(AccumulationCompositionLimits))
