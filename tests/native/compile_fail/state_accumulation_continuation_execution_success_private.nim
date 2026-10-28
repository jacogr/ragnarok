# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Reject private continuation completion payload access.

import ../../../src/state/accumulation_continuation_execution as state_accumulation_continuation_execution
var result: AccumulationContinuationExecutionResult[int]
discard result.completed
