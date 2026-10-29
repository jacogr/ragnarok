# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Current output proof representation stays private.
import ../../../src/state/accumulation/current/[outputs as accumulation_current_outputs,
    driver as accumulation_current_driver]
let refused = prepareCurrentAccumulationOutputs(default(CompletedCurrentAccumulationSequence),
    default(CurrentAccumulationOutputLimits))
discard default(PreparedCurrentAccumulationOutputs).data
