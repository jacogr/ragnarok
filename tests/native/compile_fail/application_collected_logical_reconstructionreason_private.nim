# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "reconstructionReason"}

## Collected logical result storage cannot be retagged or extracted directly.
import ../../../src/app/current_logical
let owner = default(CollectedLogicalResult)
discard owner.reconstructionReason
