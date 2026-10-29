# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "BlockAccumulationRound", "early": ["runBlockAccumulation(", "[1] expected: BlockAccumulationRound but got: CompletedBlockAccumulation"]}

## Only genuine initial-round provenance can authorize guest execution.

import ../../../src/state/accumulation/[runner as accumulation_runner,
    execution as accumulation_execution]
import ../../../src/chain/parameters
var source: CompletedBlockAccumulation
discard runBlockAccumulation(source, default(Parameters), default(AccumulationRunnerLimits))
