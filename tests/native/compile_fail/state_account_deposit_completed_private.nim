# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "completed"}

## Caller cannot forge a representable threshold or retag arithmetic refusal.
import ../../../src/state/account_deposit as state_account_deposit
var value = default(AccountDepositResult)
discard value.completed
