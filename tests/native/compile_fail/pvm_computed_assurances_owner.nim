# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private computed assurance authority and selected-result storage.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/computed/assurances as computed_assurances
var candidate: AssuredComputedReports
discard candidate.data
