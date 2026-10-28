# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject a detached report stage or numeric policy as complete source/profile context.

# @@Verification={"group": "nominal", "expected": "HistoryConfig", "early": ["checkComputedRecentAnchor(", "[2] expected: HistoryConfig but got: ByteLimit"]}

import ../../../src/state/computed_recent as state_computed_recent
import ../../../src/state/computed_state as state_computed_state
import ../../../src/state/computed_links as state_computed_links
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_history as codec_state_history
discard checkComputedRecentAnchor(default(StateBoundComputedReport), ByteLimit(1000))
