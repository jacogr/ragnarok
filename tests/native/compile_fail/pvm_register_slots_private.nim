# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw operand copies never expose the captured bounded-coordinate storage.
# @@Verification={"group": "privacy", "expected": "registerSlots"}
import ../../../src/pvm/program
let copied = default(Instruction)
discard copied.registerSlots
