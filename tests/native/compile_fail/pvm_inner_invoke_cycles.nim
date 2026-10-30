# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Preserve private nested engine reasons and independent nominal inner-segment budgets.

# @@Verification={"group": "nominal", "expected": "got: ExecutionStepLimit but wanted: GasCycleLimit"}

import ../../../src/pvm/[inner_machines, step]
import ../../../src/pvm/gas/gas
discard InnerMachineLimits(cycles: ExecutionStepLimit(1))
