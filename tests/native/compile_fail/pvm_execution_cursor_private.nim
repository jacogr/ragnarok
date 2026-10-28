# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Invocation-owned mutable CPU evaluation cannot become an externally callable snapshot bypass.
# @@Verification={"group": "privacy", "expected": "evaluateInstruction"}
import ../../../src/pvm/step as pvm_step
discard pvm_step.evaluateInstruction
