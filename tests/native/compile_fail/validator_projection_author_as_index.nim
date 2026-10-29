# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "StatisticsValidatorIndex", "early": ["projectedValidatorAt(", "[3] expected: StatisticsValidatorIndex but got: AuthorIndex"]}

## An author identifier cannot select a validator activity row.

import ../../../src/state/validator/projection as validator_projection
import ../../../src/codec/state/statistics as state_statistics
import ../../../src/codec/header
var owner: ValidatorActivityProjection
var author: AuthorIndex
discard projectedValidatorAt(owner, StatisticsEpoch.Current, author)
