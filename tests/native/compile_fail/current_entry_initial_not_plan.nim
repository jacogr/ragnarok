# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentContinuation but got: PreparedCurrentAccumulationRound"}

## Later execution accepts genuine plan authority and local policy, never replacement frame/price/index domains.
import ../../../src/state/accumulation_current_round
import ../../../src/state/accumulation_current_sequence
discard runCurrentAccumulationContinuation(default(PreparedCurrentAccumulationRound), default(CurrentContinuationExecutionLimits))
