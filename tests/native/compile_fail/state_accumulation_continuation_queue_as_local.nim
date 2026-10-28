# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "ContinuationReportIndex", "early": ["continuationReportAt(", "[2] expected: ContinuationReportIndex but got: AccumulationIndex"]}

## Refuse access or substitution across the admitted continuation planning boundary.

import ../../../src/state/accumulation_continuation as state_accumulation_continuation
import ../../../src/state/accumulation_queue as state_accumulation_queue
var plan: PreparedAccumulationContinuation
discard continuationReportAt(plan, AccumulationIndex(0))
