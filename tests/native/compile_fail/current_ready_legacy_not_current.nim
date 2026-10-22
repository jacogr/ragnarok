# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationFinalization but got: PreparedAccumulationHistory"}

## Exact current finalization ownership is required.
import ../../../src/state/[accumulation_current_ready, accumulation_ready, accumulation_history]
discard prepareCurrentAccumulationReady(default(PreparedAccumulationHistory), default(AccumulationReadyConfig))
