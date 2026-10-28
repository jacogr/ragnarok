# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw operand copies cannot expose or rewrite their owner's sealed static control fact.
# @@Verification={"group": "privacy", "expected": "targetStartsBlock"}
import ../../../src/pvm/program as pvm_program
let decoded = instruction(default(Program), CodeAddress(0))
discard decoded.value.targetStartsBlock
