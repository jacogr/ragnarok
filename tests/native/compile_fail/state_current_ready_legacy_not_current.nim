# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationFinalization but got: PreparedAccumulationHistory", "early": ["prepareCurrentAccumulationReady(", "[1] expected: PreparedCurrentAccumulationFinalization but got: PreparedAccumulationHistory"]}

## Exact current finalization ownership is required.
import ../../../src/state/accumulation_current_ready as state_accumulation_current_ready
import ../../../src/state/accumulation_ready as state_accumulation_ready
import ../../../src/state/accumulation_history as state_accumulation_history
discard prepareCurrentAccumulationReady(default(PreparedAccumulationHistory), default(AccumulationReadyConfig))
