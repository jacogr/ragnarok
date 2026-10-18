# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw integers cannot substitute for instruction addresses.
import ../../../src/pvm/[program, machine, registers]
discard evaluateRegisters(default(Program), 0'u64, default(RegisterFile))
