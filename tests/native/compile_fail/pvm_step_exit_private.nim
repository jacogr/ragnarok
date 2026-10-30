# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture protecting memory-step outcome privacy and nominal limits.
## Intentionally rejects the forbidden member access or mismatched call below.

# @@Verification={"group": "privacy", "expected": "kind"}

import ../../../src/pvm/machine
import ../../../src/pvm/gas/gas
import ../../../src/pvm/step
var outcome = default(StepOutcome)
outcome.kind = StepExit.Fault
