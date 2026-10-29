# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationReady", "early": ["prepareAccumulationRecent(", "[1] expected: PreparedAccumulationReady but got: HistorySnapshot"]}

## Loose decoded history cannot replace a finalized source certificate.

import ../../../src/state/accumulation/recent as accumulation_recent
import ../../../src/codec/state/history as state_history
var source: HistorySnapshot
var config: AccumulationRecentConfig
discard prepareAccumulationRecent(source, config)
