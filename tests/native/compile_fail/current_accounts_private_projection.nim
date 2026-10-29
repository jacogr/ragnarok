# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "projectionReason"}

## Timestamp owner and refusal representation remains private.
import ../../../src/state/accumulation/current/accounts as accumulation_current_accounts
import ../../../src/state/accumulation/accounts as accumulation_accounts
import ../../../src/state/accumulation/current/statistics as accumulation_current_statistics
let refused = prepareCurrentAccumulationAccounts(default(PreparedCurrentAccumulationStatistics),
    default(AccumulationAccountConfig))
discard refused.projectionReason
