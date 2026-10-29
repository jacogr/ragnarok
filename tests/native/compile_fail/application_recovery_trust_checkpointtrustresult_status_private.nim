# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Captured trust and selected reasons remain private immutable ownership.
import ../../../src/app/checkpoint/trust as checkpoint_trust
let owner = default(CheckpointTrustResult)
discard owner.status
