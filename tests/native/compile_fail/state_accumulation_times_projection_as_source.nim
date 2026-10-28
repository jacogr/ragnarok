# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationRecent", "early": ["prepareAccumulationTimes(", "[1] expected: PreparedAccumulationRecent but got: AccumulationTimesProjection"]}

## A loose timestamp projection cannot replace certified recent-history provenance.

import ../../../src/state/accumulation_times as state_accumulation_times
var projection: AccumulationTimesProjection
var config: AccumulationTimesConfig
discard prepareAccumulationTimes(projection, config)
