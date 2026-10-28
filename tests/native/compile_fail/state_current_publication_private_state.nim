# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "stateReason"}

## Current publication result representation stays private.
import ../../../src/state/accumulation_current_publication as state_accumulation_current_publication
import ../../../src/state/accumulation_current_consensus as state_accumulation_current_consensus
import ../../../src/state/store as state_store
var state = default(StateStore)
let refused = publishCurrentAccumulationState(state, default(PreparedCurrentAccumulationConsensus))
discard refused.stateReason
