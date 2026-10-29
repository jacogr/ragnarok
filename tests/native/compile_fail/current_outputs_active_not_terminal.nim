# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: CompletedCurrentAccumulationSequence but got: CurrentAccumulationSequence", "early": ["prepareCurrentAccumulationOutputs(", "[1] expected: CompletedCurrentAccumulationSequence but got: CurrentAccumulationSequence"]}

## An active sequence grants no terminal output authority.
import ../../../src/state/accumulation/current/[outputs as accumulation_current_outputs,
    sequence as accumulation_current_sequence]
discard prepareCurrentAccumulationOutputs(default(CurrentAccumulationSequence), default(CurrentAccumulationOutputLimits))
