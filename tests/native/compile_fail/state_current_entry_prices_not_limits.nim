# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: CurrentContinuationExecutionLimits but got: Parameters", "early": ["runCurrentAccumulationContinuation(", "[2] expected: CurrentContinuationExecutionLimits but got: Parameters"]}

## Later execution accepts genuine plan authority and local policy, never replacement frame/price/index domains.
import ../../../src/chain/parameters as chain_parameters
import ../../../src/state/accumulation_current_sequence as state_accumulation_current_sequence
discard runCurrentAccumulationContinuation(default(PreparedCurrentContinuation), default(Parameters))
