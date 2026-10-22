# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "completed"}

## Caller cannot forge expected-root account evidence or rewrite failed phase alternatives.
import ../../../src/state/planned_account_checkpoint
var value = default(PlannedAccountCheckpointResult)
discard value.completed
