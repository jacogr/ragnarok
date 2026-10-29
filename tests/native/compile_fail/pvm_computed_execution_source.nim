# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A loose block round cannot replace original computed parameter authority.

# @@Verification={"group": "nominal", "expected": "ComputedAccumulationRound", "early": ["executeComputedAccumulation(", "[1] expected: ComputedAccumulationRound but got: BlockAccumulationRound"]}

import ../../../src/state/computed/execution as computed_execution
import ../../../src/state/accumulation/[round as accumulation_round, runner as accumulation_runner]
discard executeComputedAccumulation(default(BlockAccumulationRound), AccumulationRunnerLimits())
