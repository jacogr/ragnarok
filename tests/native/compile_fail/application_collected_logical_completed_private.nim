# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "completed"}

## Collected logical result storage cannot be retagged or extracted directly.
import ../../../src/app/current/logical as current_logical
let owner = default(CollectedLogicalResult)
discard owner.completed
