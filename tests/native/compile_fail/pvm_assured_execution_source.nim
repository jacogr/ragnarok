# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bare priority queue cannot replace retained assurance provenance.

# @@Verification={"group": "nominal", "expected": "AssuredAccumulationQueue", "early": ["executeAssuredAccumulation(", "[1] expected: AssuredAccumulationQueue but got: BlockAccumulationQueue"]}

import ../../../src/state/assured/execution as assured_execution
import ../../../src/state/accumulation/queue as accumulation_queue
discard executeAssuredAccumulation(default(BlockAccumulationQueue), AssuredExecutionConfig())
