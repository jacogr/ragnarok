# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Captured wire, source storage and result alternatives remain private.
import ../../../src/state/current_checkpoint as state_current_checkpoint
var value = default(CurrentCheckpointResult[CurrentUpdateCheckpoint])
discard value.status
