# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw integers cannot substitute for instruction addresses.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/pvm/[program, machine, registers]
discard evaluateRegisters(default(Program), 0'u64, default(RegisterFile))
