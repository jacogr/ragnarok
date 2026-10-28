# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationTimes", "early": ["prepareAccumulationValidators(", "[1] expected: PreparedAccumulationTimes but got: BlockTransitionResult"]}

## Disconnected or partial-stage inputs cannot construct an accumulation validator certificate.

import ../../../src/state/accumulation_validators as state_accumulation_validators
import ../../../src/state/block_transition as state_block_transition
var source: BlockTransitionResult
var config: AccumulationValidatorsConfig
discard prepareAccumulationValidators(source, config)
