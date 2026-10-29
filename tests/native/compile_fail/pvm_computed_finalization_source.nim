# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A loose completion cannot replace the original computed execution graph.

# @@Verification={"group": "nominal", "expected": "ExecutedComputedAccumulation", "early": ["finalizeComputedAccumulation(", "[1] expected: ExecutedComputedAccumulation but got: CompletedBlockAccumulation"]}

import ../../../src/state/computed/finalization as computed_finalization
import ../../../src/state/accumulation/execution as accumulation_execution
discard finalizeComputedAccumulation(default(CompletedBlockAccumulation),
    ComputedFinalizationConfig())
