# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Checkpoint result internals cannot bypass success-guarded extraction.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/state/checkpoint
let outcome = default(CheckpointResult[seq[byte]])
discard outcome.completed
