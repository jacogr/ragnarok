# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject a detached report stage or numeric policy as complete source/profile context.

# @@Verification={"group": "nominal", "expected": "StateBoundComputedReport", "early": ["checkComputedRecentAnchor(", "[1] expected: StateBoundComputedReport but got: ComputedReportLinks"]}

import ../../../src/state/[computed_recent, computed_state, computed_links]
import ../../../src/codec/[bounded, state_history]
discard checkComputedRecentAnchor(default(ComputedReportLinks), default(HistoryConfig))
