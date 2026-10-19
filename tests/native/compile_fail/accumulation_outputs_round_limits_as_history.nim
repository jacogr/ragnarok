# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AccumulationOutputHistoryLimits", "early": ["prepareAccumulationOutputs(", "[2] expected: AccumulationOutputHistoryLimits but got: AccumulationOutputLimits"]}

## Refuse substitution across completed-history provenance and traversal-policy boundaries.

import ../../../src/state/[accumulation_outputs, accumulation_reentry]
var source: CompletedAccumulationReentry
var limits: AccumulationOutputLimits
discard prepareAccumulationOutputs(source, limits)
