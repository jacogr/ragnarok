# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Reject raw construction or retagging across statistics-bound account ownership.

import ../../../src/state/accumulation_accounts
var plan: PreparedAccumulationAccounts
discard plan.data
