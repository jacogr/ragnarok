# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject lifecycle owner/result forgery or interchange of independent nominal domains.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/pvm/inner_machines
var item: InnerMachineResult[InnerMachineTransition]
discard item.completed
