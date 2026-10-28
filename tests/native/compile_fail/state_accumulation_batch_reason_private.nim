# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "terminalReason"}

## Batch owners/results do not export raw storage or unchecked alternatives.

import ../../../src/state/accumulation_batch as state_accumulation_batch
var result: AccumulationBatchResult[PreparedAccumulationBatch]
discard result.terminalReason
