# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private computed execution authority and result selection.

# @@Verification={"group": "privacy", "expected": "runnerReason"}

import ../../../src/state/computed_execution as state_computed_execution
var candidate: ComputedExecutionResult[ExecutedComputedAccumulation]
discard candidate.runnerReason
