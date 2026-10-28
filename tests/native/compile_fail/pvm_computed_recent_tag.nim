# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged recent-anchor storage or selected result alternatives.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/computed_recent as state_computed_recent
var candidate: ComputedRecentResult[RecentComputedReport]
discard candidate.status
