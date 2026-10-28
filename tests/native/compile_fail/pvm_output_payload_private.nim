# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture for return-output privacy and the nominal byte-copy budget.
## The selected private/read-only field or raw budget must fail compilation.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/pvm/step as pvm_step
import ../../../src/pvm/output as pvm_output
let r = default(OutputResult)
discard r.completed
