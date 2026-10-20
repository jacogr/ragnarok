# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Preserve private nested engine reasons and independent nominal inner-segment budgets.

# @@Verification={"group": "privacy", "expected": "reason"}

import ../../../src/pvm/[inner_machines, step, gas]
var outcome: InnerMachineResult[InnerMachineTransition]
discard outcome.reason
