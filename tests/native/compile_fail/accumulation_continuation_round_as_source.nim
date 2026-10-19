# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "CompletedBlockAccumulation", "early": ["planAccumulationContinuation(", "[1] expected: CompletedBlockAccumulation but got: BlockAccumulationRound"]}

## Refuse access or substitution across the admitted continuation planning boundary.

import ../../../src/state/[accumulation_continuation, accumulation_round]
var round: BlockAccumulationRound
var limits: AccumulationContinuationLimits
discard planAccumulationContinuation(round, limits)
