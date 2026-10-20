# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A raw successful block stage cannot replace original computed assurance authority.

# @@Verification={"group": "nominal", "expected": "AssuredComputedReports", "early": ["prepareAssuredQueue(", "[1] expected: AssuredComputedReports but got: BlockTransitionResult"]}

import ../../../src/state/[assured_queue, block_transition]
discard prepareAssuredQueue(default(BlockTransitionResult), AssuredQueueConfig())
