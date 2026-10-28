# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Reject mutable construction or payload extraction across private recent-history ownership.

import ../../../src/state/accumulation_recent as state_accumulation_recent
var outcome: AccumulationRecentResult[PreparedAccumulationRecent]
discard outcome.completed
