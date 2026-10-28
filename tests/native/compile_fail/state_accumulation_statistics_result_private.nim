# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Refuse raw construction or retagging across the finalized statistics boundary.

import ../../../src/state/accumulation_statistics as state_accumulation_statistics
var outcome: AccumulationStatisticsResult[PreparedAccumulationStatistics]
discard outcome.completed
