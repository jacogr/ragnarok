# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "CompletedAccumulationReentry", "early": ["prepareAccumulationOutputs(", "[1] expected: CompletedAccumulationReentry but got: PreparedAccumulationReentry"]}

## Refuse substitution across completed-history provenance and traversal-policy boundaries.

import ../../../src/state/[accumulation_outputs, accumulation_reentry]
var source: PreparedAccumulationReentry
var limits: AccumulationOutputHistoryLimits
discard prepareAccumulationOutputs(source, limits)
