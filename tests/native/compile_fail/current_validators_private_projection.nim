# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "projectionReason"}

## Current validator proof representation stays private.
import ../../../src/state/[accumulation_current_validators, accumulation_validators,
    accumulation_current_recent]
let refused = prepareCurrentAccumulationValidators(default(PreparedCurrentAccumulationRecent),
    default(AccumulationValidatorsConfig))
discard refused.projectionReason
