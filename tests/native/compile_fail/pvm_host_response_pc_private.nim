# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compilation must reject external access to the causing host-call address.

# @@Verification={"group": "privacy", "expected": "callAddress"}

import ../../../src/pvm/step as pvm_step
let outcome = default(StepOutcome)
discard outcome.callAddress
