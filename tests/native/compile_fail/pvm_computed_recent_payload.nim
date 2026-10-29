# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged recent-anchor storage or selected result alternatives.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/computed/recent as computed_recent
var candidate: ComputedRecentResult[RecentComputedReport]
discard candidate.completed
