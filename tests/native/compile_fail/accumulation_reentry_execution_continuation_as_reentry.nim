# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationReentry", "early": ["completeAccumulationReentry(", "[1] expected: PreparedAccumulationReentry but got: PreparedAccumulationContinuationInputs"]}

## Reject substitution of nominal reentry bootstrap/completion provenance.

import ../../../src/state/[accumulation_reentry_execution, accumulation_continuation_inputs,
    accumulation_execution]
var old: PreparedAccumulationContinuationInputs
discard completeAccumulationReentry(old, [], [], default(AccumulationExecutionLimits))
