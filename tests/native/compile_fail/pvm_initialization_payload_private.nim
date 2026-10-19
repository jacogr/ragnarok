# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture for initialization result privacy and nominal allocation policy.
## The forbidden field access or raw limit below must fail compilation.

## Verification: {"group": "privacy", "expected": "completed"}

import ../../../src/pvm/[initialize]
let r = default(InitializationResult)
discard r.completed
