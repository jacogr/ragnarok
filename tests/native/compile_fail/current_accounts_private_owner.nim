# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Timestamp owner and refusal representation remains private.
import ../../../src/state/[accumulation_current_accounts, accumulation_accounts,
    accumulation_current_statistics]
let refused = prepareCurrentAccumulationAccounts(default(PreparedCurrentAccumulationStatistics),
    default(AccumulationAccountConfig))
discard default(PreparedCurrentAccumulationAccounts).data
