# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject safe-code access to private successful transition provenance.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/computed_transition
var candidate: TransitionBoundComputedReport
discard candidate.data
