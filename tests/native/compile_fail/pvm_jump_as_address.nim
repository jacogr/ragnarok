# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject attempts to bypass the PVM ownership/result or nominal-domain boundary.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "[2] expected: CodeAddress but got: JumpIndex", "early": ["instruction(", "[2] expected: CodeAddress but got: JumpIndex"]}

import ../../../src/pvm/program as pvm_program
discard instruction(default(Program), JumpIndex(0))
