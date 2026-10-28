# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Current recent-history proof representation stays private.
import ../../../src/state/accumulation_current_recent as state_accumulation_current_recent
import ../../../src/state/accumulation_recent as state_accumulation_recent
import ../../../src/state/accumulation_current_ready as state_accumulation_current_ready
let refused = prepareCurrentAccumulationRecent(default(PreparedCurrentAccumulationReady), default(
    AccumulationRecentConfig))
discard refused.completed
