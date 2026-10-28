# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Only invocation-owned genuine host suspensions may use the private response cursor.
# @@Verification={"group": "privacy", "expected": "applyCursorResponse"}
import ../../../src/pvm/step as pvm_step
discard pvm_step.applyCursorResponse
