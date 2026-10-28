# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture protecting memory-step outcome privacy and nominal limits.
## Intentionally rejects the forbidden member access or mismatched call below.

# @@Verification={"group": "privacy", "expected": "failedPage"}

import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/gas as pvm_gas
import ../../../src/pvm/step as pvm_step
var outcome = default(StepOutcome)
discard outcome.failedPage
