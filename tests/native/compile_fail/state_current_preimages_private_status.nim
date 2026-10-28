# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Current fulfilled-preimage proof representation stays private.
import ../../../src/state/accumulation_current_preimages as state_accumulation_current_preimages
import ../../../src/state/accumulation_preimages as state_accumulation_preimages
import ../../../src/state/accumulation_current_activity as state_accumulation_current_activity
let refused = prepareCurrentAccumulationPreimages(default(PreparedCurrentAccumulationActivity),
    default(AccumulationPreimageLimits))
discard refused.status
