# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private scalar-code authority access.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/erasure/words as erasure_words
var candidate: ErasureWordCode
discard candidate.data
