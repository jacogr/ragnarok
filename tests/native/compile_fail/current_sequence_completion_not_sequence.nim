# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: CurrentAccumulationSequence but got: PreparedCurrentAccumulationRound", "early": ["planCurrentAccumulationContinuation(", "[1] expected: CurrentAccumulationSequence but got: PreparedCurrentAccumulationRound"]}

## Current source owners and plan-local ordinal domains cannot substitute one another.
import ../../../src/state/accumulation/current/[sequence as accumulation_current_sequence,
    round as accumulation_current_round]
discard planCurrentAccumulationContinuation(default(PreparedCurrentAccumulationRound), default(CurrentContinuationLimits))
