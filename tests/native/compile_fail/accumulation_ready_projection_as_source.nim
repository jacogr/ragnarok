# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationHistory", "early": ["prepareAccumulationReady(", "[1] expected: PreparedAccumulationHistory but got: AccumulationReadyProjection"]}

## Refuse substituting a projection for bound history or a full map for a ready ring.

import ../../../src/state/[accumulation_ready]
var source: AccumulationReadyProjection
var config: AccumulationReadyConfig
discard prepareAccumulationReady(source, config)
