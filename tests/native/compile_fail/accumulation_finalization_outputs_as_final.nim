# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedFinalAccumulation", "early": ["finalAccumulationState(", "[1] expected: PreparedFinalAccumulation but got: PreparedAccumulationOutputs"]}

## Refuse substitution of a prepared prefix or output projection for a terminal full-state candidate.

import ../../../src/state/[accumulation_finalization, accumulation_outputs]
var outputs: PreparedAccumulationOutputs
discard finalAccumulationState(outputs)
