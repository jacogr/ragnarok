# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private computed composition authority and result selection.

# @@Verification={"group": "privacy", "expected": "compositionReason"}

import ../../../src/state/computed_composition
var candidate: ComputedCompositionResult[ComposedComputedState]
discard candidate.compositionReason
