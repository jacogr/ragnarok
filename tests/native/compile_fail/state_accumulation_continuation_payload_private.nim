# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Refuse access or substitution across the admitted continuation planning boundary.

import ../../../src/state/accumulation_continuation as state_accumulation_continuation
var result: AccumulationContinuationResult[PreparedAccumulationContinuation]
discard result.completed
