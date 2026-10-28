# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "fileReason"}

## Operator-file failure reasons cannot be forged through raw fields.
import ../../../src/app/checkpoint_trust as app_checkpoint_trust
let owner = default(CheckpointTrustResult)
discard owner.fileReason
