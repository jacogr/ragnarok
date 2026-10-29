# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Reject raw construction or retagging across statistics-bound account ownership.

import ../../../src/state/accumulation/accounts as accumulation_accounts
var outcome: AccumulationAccountResult[PreparedAccumulationAccounts]
outcome.status = AccumulationAccountError.None
