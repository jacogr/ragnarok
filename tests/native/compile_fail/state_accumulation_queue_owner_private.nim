# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler-rejection fixture protecting private accumulation plan/result ownership.
## Its top-level field access attempts to expose private storage; compilation must fail.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/accumulation_queue as state_accumulation_queue
let owner = default(AccumulationQueuePlan)
discard owner.data # Private storage must fail semantic compilation.
