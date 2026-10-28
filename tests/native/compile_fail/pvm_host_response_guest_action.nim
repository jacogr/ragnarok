# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture for host-response gas and action domains.
## Raw integers and guest exit reasons cannot stand in for explicit typed host replies.

# @@Verification={"group": "nominal", "expected": "got: StepExit but wanted: HostAction"}

import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/step as pvm_step
discard HostResponse(action: StepExit.Halt)
