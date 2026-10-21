# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject construction of a successful instruction result from caller-selected operand fields.
## The register evaluator accepts only private validated results, never forged mutable instructions.

# @@Verification={"expected": "status", "group": "privacy"}

import ../../../src/pvm/program
let forged = ProgramResult[Instruction](status: ProgramError.None, completed: default(Instruction))
discard forged
