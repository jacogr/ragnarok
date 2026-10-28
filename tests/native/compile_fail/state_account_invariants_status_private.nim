# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Callers cannot forge joined authority or rewrite private results.
import ../../../src/state/account_invariants as state_account_invariants
var value = default(AccountInvariantResult[CheckedAccountInvariants])
discard value.status
