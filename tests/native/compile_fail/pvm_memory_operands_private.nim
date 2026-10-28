# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw operand copies cannot expose or replace the owner-decoded memory facts.
# @@Verification={"group": "privacy", "expected": "memoryOperands"}
import ../../../src/pvm/program as pvm_program
let copied = default(Instruction)
discard copied.memoryOperands
