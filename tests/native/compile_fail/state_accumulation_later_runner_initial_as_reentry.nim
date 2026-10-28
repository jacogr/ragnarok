# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationReentry", "early": ["runAccumulationReentry(", "[1] expected: PreparedAccumulationReentry but got: BlockAccumulationRound"]}

## Each public runner requires its genuine prepared source family.

import ../../../src/state/accumulation_later_runner as state_accumulation_later_runner
import ../../../src/state/accumulation_runner as state_accumulation_runner
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/chain/parameters as chain_parameters
var source: BlockAccumulationRound
discard runAccumulationReentry(source, default(Parameters), default(AccumulationRunnerLimits))
