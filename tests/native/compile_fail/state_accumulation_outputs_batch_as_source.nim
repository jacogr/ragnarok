# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "CompletedBlockAccumulation", "early": ["prepareAccumulationOutputs(", "[1] expected: CompletedBlockAccumulation but got: PreparedAccumulationBatch"]}

## Refuse access or substitution across the admitted output projection boundary.

import ../../../src/state/accumulation_outputs as state_accumulation_outputs
import ../../../src/state/accumulation_batch as state_accumulation_batch
var batch: PreparedAccumulationBatch
var limits: AccumulationOutputLimits
discard prepareAccumulationOutputs(batch, limits)
