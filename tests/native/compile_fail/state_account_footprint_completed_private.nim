# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "completed"}

## Arithmetic result discriminators and payloads remain private.
import ../../../src/state/account_footprint
let private = default(AccountFootprintResult)
discard private.completed
