# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedFinalAccumulation", "early": ["prepareAccumulationHistory(", "[1] expected: PreparedFinalAccumulation but got: AccumulationHistoryProjection"]}

## Refuse substituting a projection for finalization or a full map for an accumulated ring.

import ../../../src/state/accumulation/history as accumulation_history
var source: AccumulationHistoryProjection
var config: AccumulationHistoryConfig
discard prepareAccumulationHistory(source, config)
