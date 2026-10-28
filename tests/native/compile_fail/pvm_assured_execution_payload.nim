# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private execution authority and selected result storage.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/assured_execution as state_assured_execution
var candidate: AssuredExecutionResult[ExecutedAssuredAccumulation]
discard candidate.completed
