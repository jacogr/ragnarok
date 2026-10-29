# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Current finalization representation remains private.
import ../../../src/state/accumulation/current/[finalization as accumulation_current_finalization,
    accounts as accumulation_current_accounts]
let refused = prepareCurrentAccumulationFinalization(default(PreparedCurrentAccumulationAccounts),
    default(CurrentAccumulationFinalizationConfig))
discard refused.status
