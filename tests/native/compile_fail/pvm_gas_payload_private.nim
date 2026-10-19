# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture for gas-result privacy or nominal simulation boundaries.
## This test intentionally fails compilation at the forbidden access or mismatched call below.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/pvm/[program, gas]
let r = default(GasResult)
discard r.completed
