# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture for step-result privacy or nominal simulation limits.
## This test intentionally fails at the forbidden field access or mismatched call below.

## Verification: {"group": "privacy", "expected": "error"}

import ../../../src/pvm/[machine, gas, step]
var r = default(StepResult)
r.error = StepError.None
