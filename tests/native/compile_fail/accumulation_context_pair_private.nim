# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compilation fixture: initial context provenance and result storage remain private.
## Direct field access must fail before a caller can forge or retag a context.

# @@Verification={"group": "privacy", "expected": "initial"}

import ../../../src/state/accumulation_context
let owner = default(PreparedAccumulationContexts)
discard owner.initial # Private storage cannot be used as a public constructor.
