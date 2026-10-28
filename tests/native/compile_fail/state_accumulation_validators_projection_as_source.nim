# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationTimes", "early": ["prepareAccumulationValidators(", "[1] expected: PreparedAccumulationTimes but got: ValidatorActivityProjection"]}

## Disconnected or partial-stage inputs cannot construct an accumulation validator certificate.

import ../../../src/state/accumulation_validators as state_accumulation_validators
import ../../../src/state/validator_projection as state_validator_projection
var source: ValidatorActivityProjection
var config: AccumulationValidatorsConfig
discard prepareAccumulationValidators(source, config)
