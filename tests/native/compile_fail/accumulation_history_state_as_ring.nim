# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AccumulatedSnapshot", "early": ["projectAccumulationHistory(", "[1] expected: AccumulatedSnapshot but got: StateStoreSnapshot"]}

## Refuse substituting a projection for finalization or a full map for an accumulated ring.

import ../../../src/state/[accumulation_history, store]
var state: StateStoreSnapshot
var config: AccumulationHistoryConfig
discard projectAccumulationHistory(state, [], config)
