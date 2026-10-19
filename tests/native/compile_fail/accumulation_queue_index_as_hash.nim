# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler-rejection fixture for separate ring, priority and dependency index domains.
## Its top-level call supplies the wrong nominal ordinal; successful compilation is a test failure.

# @@Verification={"group": "nominal", "expected": "[3] expected: WorkQueueHashIndex but got: AccumulationIndex", "early": ["accumulationDependencyAt(", "[3] expected: WorkQueueHashIndex but got: AccumulationIndex"]}

import ../../../src/state/accumulation_queue
import ../../../src/codec/state_workqueues
discard accumulationDependencyAt(default(AccumulationQueuePlan), AccumulationIndex(0),
  AccumulationIndex(0))
