# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationRound but got: PreparedAccumulationGlobalPhase", "early": ["startCurrentAccumulationSequence(", "[1] expected: PreparedCurrentAccumulationRound but got: PreparedAccumulationGlobalPhase"]}

## Current source owners and plan-local ordinal domains cannot substitute one another.
import ../../../src/state/accumulation/current/sequence as accumulation_current_sequence
import ../../../src/state/accumulation/global/phase as accumulation_global_phase
discard startCurrentAccumulationSequence(default(PreparedAccumulationGlobalPhase))
