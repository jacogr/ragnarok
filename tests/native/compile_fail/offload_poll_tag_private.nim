# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Caller code cannot inspect private completion state or payload.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "hasCompletion"}

import "../../../src/jamnp-s/offload"
let polled = default(OffloadPollResult)
discard polled.hasCompletion
