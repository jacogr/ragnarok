# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private authenticated assignment provenance and result selection.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/computed_guarantors as state_computed_guarantors
var candidate: ComputedGuarantors
discard candidate.data
