# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject a detached report stage or numeric policy as complete source/profile context.

# @@Verification={"group": "nominal", "expected": "HistoryConfig", "early": ["checkComputedRecentAnchor(", "[2] expected: HistoryConfig but got: ByteLimit"]}

import ../../../src/state/computed/[recent as computed_recent, state as computed_state,
    links as computed_links]
import ../../../src/codec/bounded
import ../../../src/codec/state/history as state_history
discard checkComputedRecentAnchor(default(StateBoundComputedReport), ByteLimit(1000))
