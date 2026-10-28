# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Validated scalar page slots belong only to the inspecting memory call; callers cannot obtain them.
# @@Verification={"group": "privacy", "expected": "scalarSpan"}
import ../../../src/pvm/machine as pvm_machine
discard pvm_machine.scalarSpan
