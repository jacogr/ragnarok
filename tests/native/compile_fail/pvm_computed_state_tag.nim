# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged state-bound owner storage or result alternatives.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/computed/state as computed_state
var candidate: ComputedStateResult[StateBoundComputedReport]
discard candidate.status
