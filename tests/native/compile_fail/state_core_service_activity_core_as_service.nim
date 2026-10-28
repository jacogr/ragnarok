# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "StatisticsServiceIndex", "early": ["projectedServiceAt(", "[2] expected: StatisticsServiceIndex but got: StatisticsCoreIndex"]}

## Core positions and numeric-service dictionary ordinals have distinct domains.

import ../../../src/state/core_service_activity as state_core_service_activity
import ../../../src/codec/state_statistics as codec_state_statistics
var owner: CoreServiceActivityProjection
var index: StatisticsCoreIndex
discard projectedServiceAt(owner, index)
