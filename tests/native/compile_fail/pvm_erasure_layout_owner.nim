# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private erasure storage access.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/erasure_layout as state_erasure_layout
var candidate: ErasureLayout
discard candidate.data
