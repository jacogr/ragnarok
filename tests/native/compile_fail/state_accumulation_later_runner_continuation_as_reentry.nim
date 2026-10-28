# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationReentry", "early": ["runAccumulationReentry(", "[1] expected: PreparedAccumulationReentry but got: PreparedAccumulationContinuationInputs"]}

## Each public runner requires its genuine prepared source family.

import ../../../src/state/accumulation_later_runner as state_accumulation_later_runner
import ../../../src/state/accumulation_runner as state_accumulation_runner
import ../../../src/state/accumulation_continuation_inputs as state_accumulation_continuation_inputs
import ../../../src/chain/parameters as chain_parameters
var source: PreparedAccumulationContinuationInputs
discard runAccumulationReentry(source, default(Parameters), default(AccumulationRunnerLimits))
