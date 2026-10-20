# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private scalar-code authority access.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/erasure_words
var candidate: ErasureWordResult[ErasureWordCode]
discard candidate.completed
