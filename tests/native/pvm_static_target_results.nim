# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime-selected failed decodes grant no static control fact; valid targets and genuine invalid targets are positive controls.
import std/[assertions, cmdline]
import ../../src/pvm/program
let origin = paramStr(1)
var decoded = default(ProgramResult[Instruction])
if origin == "invalid":
  decoded = instruction(default(Program), CodeAddress(0))
elif origin == "unmarked":
  let owner = decodeProgram([0'u8, 0, 4, 51, 0, 7, 0, 9], CodeAddress(0), ProgramByteLimit(8),
      JumpCountLimit(0)).value
  decoded = instruction(owner, CodeAddress(1))
elif origin == "valid":
  let owner = decodeProgram([0'u8, 0, 2, 1, 0, 3], CodeAddress(0), ProgramByteLimit(6),
      JumpCountLimit(0)).value
  decoded = instruction(owner, CodeAddress(0))
  assert decoded.error == ProgramError.None and instructionTargetStartsBlock(decoded)
  assert not instructionTargetStartsBlock(instruction(owner, CodeAddress(1)))
  let negative = decodeProgram([0'u8, 0, 2, 40, 255, 1], CodeAddress(0), ProgramByteLimit(6),
      JumpCountLimit(0)).value
  assert not instructionTargetStartsBlock(instruction(negative, CodeAddress(0)))
else:
  assert origin == "default"
if origin != "valid":
  discard instructionTargetStartsBlock(decoded) # Missing/failed selection must terminate at the success-only precondition.
