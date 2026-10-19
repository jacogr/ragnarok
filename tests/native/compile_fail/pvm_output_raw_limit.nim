# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture for return-output privacy and the nominal byte-copy budget.
## The selected private/read-only field or raw budget must fail compilation.

## Verification: {"group": "nominal", "expected": "[2] expected: OutputByteLimit but got: uint64", "early": ["captureOutput(", "[2] expected: OutputByteLimit but got: uint64"]}

import ../../../src/pvm/[step, output]
let outcome = default(StepOutcome)
discard captureOutput(outcome, 0'u64)
