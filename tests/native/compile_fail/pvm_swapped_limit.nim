# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject attempts to bypass the PVM ownership/result or nominal-domain boundary.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "[3] expected: ProgramByteLimit but got: JumpCountLimit", "early": ["decodeProgram(", "[3] expected: ProgramByteLimit but got: JumpCountLimit"]}

import ../../../src/pvm/program
discard decodeProgram([], CodeAddress(0), JumpCountLimit(0), JumpCountLimit(0))
