# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "StatisticsServiceIndex", "early": ["statisticsAt(", "[2] expected: StatisticsServiceIndex but got: InvocationServiceIndex"]}

## Refuse substitution across finalized-source and nominal statistics-ordinal boundaries.

import ../../../src/state/accumulation/[statistics as accumulation_statistics,
    inputs as accumulation_inputs]
var plan: PreparedAccumulationStatistics
discard statisticsAt(plan, InvocationServiceIndex(0))
