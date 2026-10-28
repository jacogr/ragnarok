# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Reject raw construction or retagging across statistics-bound account ownership.

import ../../../src/state/accumulation_accounts as state_accumulation_accounts
var outcome: AccumulationAccountResult[PreparedAccumulationAccounts]
discard outcome.completed
