# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Checkpoint file results expose neither mutable alternatives nor unguarded restoration payloads.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/state/checkpoint/file as checkpoint_file
import ../../../src/state/store
let outcome = default(CheckpointFileResult[StateStore])
discard outcome.completed
