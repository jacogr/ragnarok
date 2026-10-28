# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "completed"}

## Host logical authority and backing storage remain private and cannot be retagged or substituted.
import ../../../src/app/logical_checkpoint as app_logical_checkpoint
let source = default(LogicalCheckpointResult)
discard source.completed
