# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "stateReason"}

## Current composed-state proof representation stays private.
import ../../../src/state/[accumulation_current_consensus, accumulation_consensus,
    accumulation_current_authorization]
let refused = prepareCurrentAccumulationConsensus(default(PreparedCurrentAccumulationAuthorization),
    default(AccumulationConsensusLimits))
discard refused.stateReason
