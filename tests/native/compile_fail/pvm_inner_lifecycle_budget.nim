# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject lifecycle owner/result forgery or interchange of independent nominal domains.

# @@Verification={"group": "nominal", "expected": "got: InnerProgramLimit but wanted: ProgramByteLimit"}

import ../../../src/pvm/inner_machines as pvm_inner_machines
import ../../../src/pvm/program as pvm_program
let item: ProgramByteLimit = InnerProgramLimit(6)
discard item
