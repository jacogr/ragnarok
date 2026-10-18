# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Each invocation must fail at the public register-result success precondition.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/cmdline
import ../../src/pvm/[program, machine, registers]
let selection = paramStr(1)
var outcome = default(RegisterResult)
# Select runtime failures so the intended assertion, not constant-folded rejection, is exercised.
if selection == "invalid-value":
  outcome = evaluateRegisters(default(Program), CodeAddress(0), default(RegisterFile))
elif selection == "unsupported-value":
  # A valid trap is outside the register-only evaluator and carries no updated registers.
  let program = decodeProgram([0'u8, 0, 1, 0, 1], CodeAddress(0),
    ProgramByteLimit(5), JumpCountLimit(0))
  outcome = evaluateRegisters(program.value, CodeAddress(0), default(RegisterFile))
else:
  # Default is explicitly uninitialized and must not expose a zero-valued register array.
  discard
discard outcome.value
