# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture protecting memory-step outcome privacy and nominal limits.
## Intentionally rejects the forbidden member access or mismatched call below.

## Verification: {"group": "nominal", "expected": "[2] expected: GasCycleLimit but got: uint64", "early": ["stepMemory(", "[2] expected: GasCycleLimit but got: uint64"]}

import ../../../src/pvm/[machine, gas, step]
discard stepMemory(default(Machine), 0'u64)
