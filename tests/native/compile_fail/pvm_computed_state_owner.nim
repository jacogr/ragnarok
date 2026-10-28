# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged state-bound owner storage or result alternatives.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/computed_state as state_computed_state
var candidate: StateBoundComputedReport
discard candidate.data
