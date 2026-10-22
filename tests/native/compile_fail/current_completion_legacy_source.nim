# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: CompletedCurrentAccumulationSequence but got: PreparedFinalAccumulation", "early": ["prepareCurrentAccumulationComposition(", "[1] expected: CompletedCurrentAccumulationSequence but got: PreparedFinalAccumulation"]}

## Legacy finalization is not proof of current sequence termination.
import ../../../src/state/[accumulation_current_completion, accumulation_finalization]
discard prepareCurrentAccumulationComposition(default(PreparedFinalAccumulation), default(CurrentAccumulationCompositionLimits))
