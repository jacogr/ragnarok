# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "identityReason"}

## Captured trust and selected reasons remain private immutable ownership.
import ../../../src/app/checkpoint_trust as app_checkpoint_trust
let owner = default(CheckpointTrustResult)
discard owner.identityReason
