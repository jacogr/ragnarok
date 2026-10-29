# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedFinalAccumulation", "early": ["prepareAccumulationStatistics(", "[1] expected: PreparedFinalAccumulation but got: CompletedAccumulationReentry"]}

## Refuse substitution across finalized-source and nominal statistics-ordinal boundaries.

import ../../../src/state/accumulation/[statistics as accumulation_statistics,
    reentry as accumulation_reentry]
var source: CompletedAccumulationReentry
var limits: AccumulationStatisticsLimits
discard prepareAccumulationStatistics(source, limits)
