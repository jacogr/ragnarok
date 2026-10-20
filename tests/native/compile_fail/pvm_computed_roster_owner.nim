# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private roster provenance or successful result selection.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/computed_roster
var candidate: RosterEligibleComputedReport
discard candidate.data
