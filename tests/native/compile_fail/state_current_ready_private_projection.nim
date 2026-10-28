# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "projectionReason"}

## Current ready proof representation stays private.
import ../../../src/state/accumulation_current_ready as state_accumulation_current_ready
import ../../../src/state/accumulation_ready as state_accumulation_ready
import ../../../src/state/accumulation_current_finalization as state_accumulation_current_finalization
let refused = prepareCurrentAccumulationReady(default(PreparedCurrentAccumulationFinalization),
    default(AccumulationReadyConfig))
discard refused.projectionReason
