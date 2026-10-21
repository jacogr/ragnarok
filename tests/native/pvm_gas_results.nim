# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative runtime fixture for the public gas-result success precondition.
## The executable selects a failure by command-line argument and attempts forbidden cost access.

import std/[cmdline, assertions]
import ../../src/pvm/[program, gas]
let selection = paramStr(1)
var outcome = default(GasResult)
# Dynamic selection preserves runtime contract checking rather than constant-folded rejection.
if selection == "invalid":
  outcome = blockGas(default(Program), CodeAddress(0), GasCycleLimit(100))
elif selection == "limit":
  # A valid trap still needs pipeline cycles before it has a completed cost.
  let owner = decodeProgram([0'u8, 0, 1, 0, 1], CodeAddress(0),
    ProgramByteLimit(5), JumpCountLimit(0))
  outcome = blockGas(owner.value, CodeAddress(0), GasCycleLimit(0))
elif selection in ["negative", "interior"]:
  # The approved negative-target price is a positive control; an unmarked operand start remains a local refusal.
  let owner = decodeProgram([0'u8, 0, 7, 170, 0, 255, 255, 255, 255, 0, 65],
    CodeAddress(0), ProgramByteLimit(11), JumpCountLimit(0))
  outcome = blockGas(owner.value, CodeAddress(if selection == "interior": 1 else: 0), GasCycleLimit(100))
else:
  # Default is an uninitialized alternative, never a free zero-cost block.
  discard
if selection == "negative":
  assert uint64(outcome.value) == 1 # A genuine successful former-gate input cannot be accepted as a failing misuse probe.
else:
  discard outcome.value # Every declared negative case attempts forbidden cost extraction.
