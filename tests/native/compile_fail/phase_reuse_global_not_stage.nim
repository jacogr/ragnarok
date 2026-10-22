# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedAccumulationGlobalStage but got: PreparedAccumulationGlobalPhase", "early": ["globalStageSnapshot(", "[1] expected: PreparedAccumulationGlobalStage but got: PreparedAccumulationGlobalPhase"]}

## Pure selected state cannot replace authenticated initial-stage ownership.
import ../../../src/state/[accumulation_global_stage, accumulation_global_phase, accumulation_provisions]
discard globalStageSnapshot(default(PreparedAccumulationGlobalPhase))
