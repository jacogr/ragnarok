# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject safe-code access to private successful transition provenance.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/computed_transition as state_computed_transition
var candidate: ComputedTransitionResult[TransitionBoundComputedReport]
discard candidate.completed
