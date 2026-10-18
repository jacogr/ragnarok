# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture for step-result privacy or nominal simulation limits.
## This test intentionally fails at the forbidden field access or mismatched call below.

import ../../../src/pvm/[machine, gas, step]
discard stepRegisters(default(Machine), 100'u64)
