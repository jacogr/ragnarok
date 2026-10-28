# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture for gas-result privacy or nominal simulation boundaries.
## This test intentionally fails compilation at the forbidden access or mismatched call below.

# @@Verification={"group": "nominal", "expected": "[3] expected: GasCycleLimit but got: uint64", "early": ["blockGas(", "[3] expected: GasCycleLimit but got: uint64"]}

import ../../../src/pvm/program as pvm_program
import ../../../src/pvm/gas as pvm_gas
discard blockGas(default(Program), CodeAddress(0), 100'u64)
