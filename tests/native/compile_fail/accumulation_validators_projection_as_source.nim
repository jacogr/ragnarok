# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationTimes", "early": ["prepareAccumulationValidators(", "[1] expected: PreparedAccumulationTimes but got: ValidatorActivityProjection"]}

## Disconnected or partial-stage inputs cannot construct an accumulation validator certificate.

import ../../../src/state/accumulation/validators as accumulation_validators
import ../../../src/state/validator/projection as validator_projection
var source: ValidatorActivityProjection
var config: AccumulationValidatorsConfig
discard prepareAccumulationValidators(source, config)
