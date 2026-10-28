# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged configured-profile storage or result alternatives.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/computed_profile as state_computed_profile
var candidate: ConfiguredComputedReport
discard candidate.data
