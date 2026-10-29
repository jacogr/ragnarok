# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "BlockAccumulationRound", "early": ["completeBlockAccumulation(", "[1] expected: BlockAccumulationRound but got: InitialAccumulationRound"]}

## Refuse access or substitution across the admitted execution certificate boundary.

import ../../../src/state/accumulation/[execution as accumulation_execution,
    round as accumulation_round]
var pure: InitialAccumulationRound
var limits: AccumulationExecutionLimits
discard completeBlockAccumulation(pure, [], [], limits)
