# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Current publication result representation stays private.
import ../../../src/state/[accumulation_current_publication, accumulation_current_consensus, store]
var state = default(StateStore)
let refused = publishCurrentAccumulationState(state, default(PreparedCurrentAccumulationConsensus))
discard refused.status
