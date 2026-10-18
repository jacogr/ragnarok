# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject attempts to bypass the PVM ownership/result or nominal-domain boundary.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/pvm/program
let result = default(ProgramResult[Program])
discard result.completed
