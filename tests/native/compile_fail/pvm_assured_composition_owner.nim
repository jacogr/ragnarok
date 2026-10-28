# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private composed authority and selected result storage.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/assured_composition as state_assured_composition
var candidate: ComposedAssuredState
discard candidate.data
