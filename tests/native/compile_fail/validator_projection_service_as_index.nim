# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "StatisticsValidatorIndex", "early": ["projectedValidatorAt(", "[3] expected: StatisticsValidatorIndex but got: ServiceIndex"]}

## A service identifier cannot select a validator activity row.

import ../../../src/state/validator_projection
import ../../../src/codec/[state_statistics, bounded]
var owner: ValidatorActivityProjection
var service: ServiceIndex
discard projectedValidatorAt(owner, StatisticsEpoch.Current, service)
