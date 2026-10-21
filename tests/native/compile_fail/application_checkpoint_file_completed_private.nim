# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## File status and selected payloads cannot be rewritten by consumers.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/app/checkpoint_file
import ../../../src/state/store
let outcome = default(ApplicationCheckpointFileResult[StateStore])
discard outcome.completed
