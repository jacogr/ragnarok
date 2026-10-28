# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "BlockAccumulationRound", "early": ["runBlockAccumulation(", "[1] expected: BlockAccumulationRound but got: InitialAccumulationRound"]}

## Only genuine initial-round provenance can authorize guest execution.

import ../../../src/state/accumulation_runner as state_accumulation_runner
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/chain/parameters as chain_parameters
var source: InitialAccumulationRound
discard runBlockAccumulation(source, default(Parameters), default(AccumulationRunnerLimits))
