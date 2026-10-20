# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged executed-input authority through private storage.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/input_refinement
var candidate: InputRefinement
discard candidate.data
