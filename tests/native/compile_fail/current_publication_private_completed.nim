# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Current publication result representation stays private.
import ../../../src/state/accumulation/current/[publication as accumulation_current_publication,
    consensus as accumulation_current_consensus]
import ../../../src/state/store
var state = default(StateStore)
let refused = publishCurrentAccumulationState(state, default(PreparedCurrentAccumulationConsensus))
discard refused.completed
