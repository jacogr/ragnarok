# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationContinuationInputs", "early": ["runAccumulationContinuation(", "[1] expected: PreparedAccumulationContinuationInputs but got: PreparedAccumulationReentry"]}

## Each public runner requires its genuine prepared source family.

import ../../../src/state/accumulation/[later_runner as accumulation_later_runner,
    runner as accumulation_runner, reentry as accumulation_reentry]
import ../../../src/chain/parameters
var source: PreparedAccumulationReentry
discard runAccumulationContinuation(source, default(Parameters), default(AccumulationRunnerLimits))
