# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler-rejection fixture for separate ring, priority and dependency index domains.
## Its top-level call supplies the wrong nominal ordinal; successful compilation is a test failure.

# @@Verification={"group": "nominal", "expected": "[2] expected: AccumulationIndex but got: WorkQueueSlot", "early": ["accumulationAt(", "[2] expected: AccumulationIndex but got: WorkQueueSlot"]}

import ../../../src/state/accumulation/queue as accumulation_queue
import ../../../src/codec/state/workqueues as state_workqueues
discard accumulationAt(default(AccumulationQueuePlan), WorkQueueSlot(0))
