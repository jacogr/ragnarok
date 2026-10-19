# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture for bounded-execution metadata privacy and nominal limits.
## Intentionally rejects the forbidden field access or mismatched argument below.

## Verification: {"group": "privacy", "expected": "callNumber"}

import ../../../src/pvm/[machine, gas, step]
var outcome = default(StepOutcome)
discard outcome.callNumber
