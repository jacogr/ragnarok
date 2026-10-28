# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Current statistics result storage stays private.
import ../../../src/state/accumulation_current_statistics as state_accumulation_current_statistics
import ../../../src/state/accumulation_current_driver as state_accumulation_current_driver
let refused = prepareCurrentAccumulationStatistics(default(CompletedCurrentAccumulationSequence),
    default(CurrentAccumulationStatisticsLimits))
discard refused.status
