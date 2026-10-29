# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compilation fixture: initial context provenance and result storage remain private.
## Direct field access must fail before a caller can forge or retag a context.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/accumulation/context as accumulation_context
let owner = default(AccumulationContextResult[PreparedAccumulationContexts])
discard owner.completed # Private storage cannot be used as a public constructor.
