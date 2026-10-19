# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture protecting memory-step outcome privacy and nominal limits.
## Intentionally rejects the forbidden member access or mismatched call below.

## Verification: {"group": "privacy", "expected": "exit"}

import ../../../src/pvm/[machine, gas, step]
var outcome = default(StepOutcome)
outcome.exit = StepExit.Fault
