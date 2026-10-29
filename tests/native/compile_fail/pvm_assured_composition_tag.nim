# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private composed authority and selected result storage.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/assured/composition as assured_composition
var candidate: AssuredCompositionResult[ComposedAssuredState]
discard candidate.status
