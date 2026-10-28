# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Current output proof representation stays private.
import ../../../src/state/accumulation_current_outputs as state_accumulation_current_outputs
import ../../../src/state/accumulation_current_driver as state_accumulation_current_driver
let refused = prepareCurrentAccumulationOutputs(default(CompletedCurrentAccumulationSequence),
    default(CurrentAccumulationOutputLimits))
discard default(PreparedCurrentAccumulationOutputs).data
