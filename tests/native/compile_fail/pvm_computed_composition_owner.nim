# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private computed composition authority and result selection.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/computed/composition as computed_composition
var candidate: ComposedComputedState
discard candidate.data
