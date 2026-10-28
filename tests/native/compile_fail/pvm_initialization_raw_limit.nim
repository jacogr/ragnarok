# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture for initialization result privacy and nominal allocation policy.
## The forbidden field access or raw limit below must fail compilation.

# @@Verification={"group": "nominal", "expected": "got: uint64 but wanted: InitializationByteLimit"}

import ../../../src/pvm/initialize as pvm_initialize
discard InitializationLimits(envelope: 20'u64)
