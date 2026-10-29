# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "source"}

## Callers cannot forge joined authority or rewrite private results.
import ../../../src/state/account/invariants as account_invariants
var value = default(CheckedAccountInvariants)
discard value.source
