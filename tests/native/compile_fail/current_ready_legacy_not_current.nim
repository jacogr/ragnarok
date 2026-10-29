# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationFinalization but got: PreparedAccumulationHistory", "early": ["prepareCurrentAccumulationReady(", "[1] expected: PreparedCurrentAccumulationFinalization but got: PreparedAccumulationHistory"]}

## Exact current finalization ownership is required.
import ../../../src/state/accumulation/current/ready as accumulation_current_ready
import ../../../src/state/accumulation/[ready as accumulation_ready,
    history as accumulation_history]
discard prepareCurrentAccumulationReady(default(PreparedAccumulationHistory), default(AccumulationReadyConfig))
