# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Current validator proof representation stays private.
import ../../../src/state/accumulation_current_validators as state_accumulation_current_validators
import ../../../src/state/accumulation_validators as state_accumulation_validators
import ../../../src/state/accumulation_current_recent as state_accumulation_current_recent
let refused = prepareCurrentAccumulationValidators(default(PreparedCurrentAccumulationRecent),
    default(AccumulationValidatorsConfig))
discard refused.status
