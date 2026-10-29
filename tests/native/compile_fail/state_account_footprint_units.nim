# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "AccountStorageItems", "early": ["itemsOnly(", "[1] expected: AccountStorageItems but got: AccountStorageBytes"]}

## Octets cannot implicitly substitute for E4 storage items.
import ../../../src/state/account/footprint as account_footprint
import ../../../src/codec/state/accounts as state_accounts
proc itemsOnly(value: AccountStorageItems) = discard # Compile-only nominal consumer.
let observation = default(AccountFootprint)
itemsOnly(observation.bytes)
