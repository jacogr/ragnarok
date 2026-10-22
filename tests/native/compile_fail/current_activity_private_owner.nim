# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Current activity proof representation stays private.
import ../../../src/state/[accumulation_current_activity, accumulation_activity,
    accumulation_current_validators]
let refused = prepareCurrentAccumulationActivity(default(PreparedCurrentAccumulationValidators),
    default(AccumulationActivityConfig))
discard default(PreparedCurrentAccumulationActivity).data
