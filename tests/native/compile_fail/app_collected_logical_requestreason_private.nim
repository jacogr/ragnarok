# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "requestReason"}

## Collected logical result storage cannot be retagged or extracted directly.
import ../../../src/app/current_logical as app_current_logical
let owner = default(CollectedLogicalResult)
discard owner.requestReason
