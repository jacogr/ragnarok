# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "StatisticsCoreIndex", "early": ["projectedCoreAt(", "[2] expected: StatisticsCoreIndex but got: StatisticsServiceIndex"]}

## Core positions and numeric-service dictionary ordinals have distinct domains.

import ../../../src/state/core_service_activity as state_core_service_activity
import ../../../src/codec/state_statistics as codec_state_statistics
var owner: CoreServiceActivityProjection
var index: StatisticsServiceIndex
discard projectedCoreAt(owner, index)
