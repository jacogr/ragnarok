# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Preserve private nested engine reasons and independent nominal inner-segment budgets.

# @@Verification={"group": "nominal", "expected": "got: GasCycleLimit but wanted: ExecutionStepLimit"}

import ../../../src/pvm/inner_machines as pvm_inner_machines
import ../../../src/pvm/step as pvm_step
import ../../../src/pvm/gas as pvm_gas
discard InnerMachineLimits(steps: GasCycleLimit(1))
