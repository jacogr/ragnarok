# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "globalReason"}

## Phase storage and successful state ownership remain private behind guarded accessors.
import ../../../src/state/validated_checkpoint as state_validated_checkpoint
let private = default(ValidatedCheckpointResult)
discard private.globalReason
