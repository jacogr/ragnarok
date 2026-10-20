# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private erasure storage access.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/erasure_layout
var candidate: ErasureLayoutResult[ErasureLayout]
discard candidate.status
