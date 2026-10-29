# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Current recent-history proof representation stays private.
import ../../../src/state/accumulation/current/recent as accumulation_current_recent
import ../../../src/state/accumulation/recent as accumulation_recent
import ../../../src/state/accumulation/current/ready as accumulation_current_ready
let refused = prepareCurrentAccumulationRecent(default(PreparedCurrentAccumulationReady), default(
    AccumulationRecentConfig))
discard default(PreparedCurrentAccumulationRecent).data
