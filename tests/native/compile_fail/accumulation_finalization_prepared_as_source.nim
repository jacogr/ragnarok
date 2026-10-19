# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "CompletedAccumulationReentry", "early": ["prepareFinalAccumulation(", "[1] expected: CompletedAccumulationReentry but got: PreparedAccumulationReentry"]}

## Refuse substitution of a prepared prefix or output projection for a terminal full-state candidate.

import ../../../src/state/[accumulation_finalization, accumulation_outputs, accumulation_reentry]
var source: PreparedAccumulationReentry
var limits: AccumulationOutputHistoryLimits
discard prepareFinalAccumulation(source, limits)
