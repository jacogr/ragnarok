# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "AccountBalance", "early": ["coversAccountMinimum(", "[3] expected: AccountBalance but got: AccountStorageBytes"]}

## Storage octets cannot substitute for a token threshold.
import ../../../src/state/account_deposit
import ../../../src/codec/state_accounts
discard coversAccountMinimum(AccountBalance(1), AccountBalance(2), AccountStorageBytes(3))
