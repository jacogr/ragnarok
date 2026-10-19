# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationContinuationInputs", "early": ["completeAccumulationContinuation(", "[1] expected: PreparedAccumulationContinuationInputs but got: CompletedBlockAccumulation"]}

## Reject replacement of nominal continuation completion provenance.

import ../../../src/state/[accumulation_continuation_execution, accumulation_execution]
var initial: CompletedBlockAccumulation
discard completeAccumulationContinuation(initial, [], [], default(AccumulationExecutionLimits))
