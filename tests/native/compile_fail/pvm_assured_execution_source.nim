# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bare priority queue cannot replace retained assurance provenance.

# @@Verification={"group": "nominal", "expected": "AssuredAccumulationQueue", "early": ["executeAssuredAccumulation(", "[1] expected: AssuredAccumulationQueue but got: BlockAccumulationQueue"]}

import ../../../src/state/assured_execution as state_assured_execution
import ../../../src/state/accumulation_queue as state_accumulation_queue
discard executeAssuredAccumulation(default(BlockAccumulationQueue), AssuredExecutionConfig())
