# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "stateReason"}

## Current composed-state proof representation stays private.
import ../../../src/state/accumulation_current_consensus as state_accumulation_current_consensus
import ../../../src/state/accumulation_consensus as state_accumulation_consensus
import ../../../src/state/accumulation_current_authorization as state_accumulation_current_authorization
let refused = prepareCurrentAccumulationConsensus(default(PreparedCurrentAccumulationAuthorization),
    default(AccumulationConsensusLimits))
discard refused.stateReason
