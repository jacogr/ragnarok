# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationReentry", "early": ["runAccumulationReentry(", "[1] expected: PreparedAccumulationReentry but got: PreparedAccumulationContinuationInputs"]}

## Each public runner requires its genuine prepared source family.

import ../../../src/state/accumulation/[later_runner as accumulation_later_runner,
    runner as accumulation_runner]
import ../../../src/state/accumulation/continuation/inputs as accumulation_continuation_inputs
import ../../../src/chain/parameters
var source: PreparedAccumulationContinuationInputs
discard runAccumulationReentry(source, default(Parameters), default(AccumulationRunnerLimits))
