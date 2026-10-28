# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedAccumulationGlobalStage but got: PreparedAccumulationGlobalPhase", "early": ["globalStageSnapshot(", "[1] expected: PreparedAccumulationGlobalStage but got: PreparedAccumulationGlobalPhase"]}

## Pure selected state cannot replace authenticated initial-stage ownership.
import ../../../src/state/accumulation_global_stage as state_accumulation_global_stage
import ../../../src/state/accumulation_global_phase as state_accumulation_global_phase
import ../../../src/state/accumulation_provisions as state_accumulation_provisions
discard globalStageSnapshot(default(PreparedAccumulationGlobalPhase))
