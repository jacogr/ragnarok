# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Current fulfilled-preimage proof representation stays private.
import ../../../src/state/[accumulation_current_preimages, accumulation_preimages,
    accumulation_current_activity]
let refused = prepareCurrentAccumulationPreimages(default(PreparedCurrentAccumulationActivity),
    default(AccumulationPreimageLimits))
discard default(PreparedCurrentAccumulationPreimages).data
