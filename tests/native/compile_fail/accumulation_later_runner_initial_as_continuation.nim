# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationContinuationInputs", "early": ["runAccumulationContinuation(", "[1] expected: PreparedAccumulationContinuationInputs but got: BlockAccumulationRound"]}

## Each public runner requires its genuine prepared source family.

import ../../../src/state/accumulation/[later_runner as accumulation_later_runner,
    runner as accumulation_runner, round as accumulation_round]
import ../../../src/chain/parameters
var source: BlockAccumulationRound
discard runAccumulationContinuation(source, default(Parameters), default(AccumulationRunnerLimits))
