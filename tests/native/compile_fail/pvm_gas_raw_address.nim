# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture for gas-result privacy or nominal simulation boundaries.
## This test intentionally fails compilation at the forbidden access or mismatched call below.

# @@Verification={"group": "nominal", "expected": "[2] expected: CodeAddress but got: uint64", "early": ["blockGas(", "[2] expected: CodeAddress but got: uint64"]}

import ../../../src/pvm/program
import ../../../src/pvm/gas/gas
discard blockGas(default(Program), 0'u64, GasCycleLimit(100))
