# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: CompletedBlockAccumulation but got: PreparedCurrentAccumulationRound", "early": ["executionInfo(", "[1] expected: CompletedBlockAccumulation but got: PreparedCurrentAccumulationRound"]}

## Current parallel round success is not legacy completed-block/history authorization.
import ../../../src/chain/parameters
import ../../../src/state/[accumulation_current_round, accumulation_round, accumulation_execution]
let refused = runCurrentBlockAccumulationRound(default(BlockAccumulationRound), default(Parameters),
    default(CurrentAccumulationRoundLimits))
discard executionInfo(refused.value)
