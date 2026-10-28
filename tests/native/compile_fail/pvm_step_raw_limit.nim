# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture for step-result privacy or nominal simulation limits.
## This test intentionally fails at the forbidden field access or mismatched call below.

# @@Verification={"group": "nominal", "expected": "[2] expected: GasCycleLimit but got: uint64", "early": ["stepRegisters(", "[2] expected: GasCycleLimit but got: uint64"]}

import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/gas as pvm_gas
import ../../../src/pvm/step as pvm_step
discard stepRegisters(default(Machine), 100'u64)
