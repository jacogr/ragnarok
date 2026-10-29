# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compilation fixture protecting private non-executing outcomes and source/result storage.
## Direct field access must fail before a caller can forge state or retag a failed outcome.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/accumulation/skip as accumulation_skip
let owner = default(SkippedAccumulation)
discard owner.data # Successful storage remains private.
