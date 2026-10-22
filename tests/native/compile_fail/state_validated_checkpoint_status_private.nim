# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Phase storage and successful state ownership remain private behind guarded accessors.
import ../../../src/state/validated_checkpoint
let private = default(ValidatedCheckpointResult)
discard private.status
