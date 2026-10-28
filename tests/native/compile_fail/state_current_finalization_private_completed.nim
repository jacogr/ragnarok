# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Current finalization representation remains private.
import ../../../src/state/accumulation_current_finalization as state_accumulation_current_finalization
import ../../../src/state/accumulation_current_accounts as state_accumulation_current_accounts
let refused = prepareCurrentAccumulationFinalization(default(PreparedCurrentAccumulationAccounts),
    default(CurrentAccumulationFinalizationConfig))
discard refused.completed
