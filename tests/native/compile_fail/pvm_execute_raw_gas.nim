# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture for bounded-execution metadata privacy and nominal limits.
## Intentionally rejects the forbidden field access or mismatched argument below.

## Verification: {"group": "nominal", "expected": "[3] expected: GasCycleLimit but got: uint64", "early": ["execute(", "[3] expected: GasCycleLimit but got: uint64"]}

import ../../../src/pvm/[machine, gas, step]
discard execute(default(Machine), ExecutionStepLimit(1), 1'u64)
