# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler-rejection fixture for separate ring, priority and dependency index domains.
## Its top-level call supplies the wrong nominal ordinal; successful compilation is a test failure.

import ../../../src/state/accumulation_queue
import ../../../src/codec/state_workqueues
discard default(AccumulationQueuePlan).accumulationDependencyAt(AccumulationIndex(0),
    AccumulationIndex(0))
