# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private erasure storage access.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/erasure/layout as erasure_layout
var candidate: ErasureLayoutResult[ErasureLayout]
discard candidate.completed
