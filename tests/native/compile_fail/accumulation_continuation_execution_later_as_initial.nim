# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "CompletedBlockAccumulation", "early": ["planAccumulationContinuation(", "[1] expected: CompletedBlockAccumulation but got: CompletedAccumulationContinuation"]}

## Reject replacement of nominal continuation completion provenance.

import ../../../src/state/[accumulation_continuation_execution, accumulation_continuation]
var later: CompletedAccumulationContinuation
discard planAccumulationContinuation(later, default(AccumulationContinuationLimits))
