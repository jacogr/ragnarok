# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject lifecycle owner/result forgery or interchange of independent nominal domains.

# @@Verification={"group": "nominal", "expected": "got: InnerMachineLimit but wanted: InnerMachineId"}

import ../../../src/pvm/inner_machines as pvm_inner_machines
import ../../../src/pvm/program as pvm_program
let item: InnerMachineId = InnerMachineLimit(0)
discard item
