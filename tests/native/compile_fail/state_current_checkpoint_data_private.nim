# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "data"}

## Captured wire, source storage and result alternatives remain private.
import ../../../src/state/current/checkpoint as current_checkpoint
var value = default(CurrentUpdateCheckpoint)
discard value.data
