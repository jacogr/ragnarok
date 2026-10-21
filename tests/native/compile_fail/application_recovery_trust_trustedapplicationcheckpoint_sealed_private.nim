# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "sealed"}

## Captured trust and selected reasons remain private immutable ownership.
import ../../../src/app/checkpoint_trust
let owner = default(TrustedApplicationCheckpoint)
discard owner.sealed
