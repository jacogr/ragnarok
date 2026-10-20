# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged configured-profile storage or result alternatives.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/computed_profile
var candidate: ComputedProfileResult[ConfiguredComputedReport]
discard candidate.completed
