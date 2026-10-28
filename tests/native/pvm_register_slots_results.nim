# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default decodes grant no register-coordinate query; genuine coordinates survive raw-copy changes and owner release.
import std/assertions
import std/cmdline
import ../../src/pvm/program as pvm_program
let origin = paramStr(1)
var decoded = default(ProgramResult[Instruction])
if origin == "invalid":
  decoded = instruction(default(Program), CodeAddress(0))
elif origin == "unmarked":
  let owner = decodeProgram([0'u8, 0, 4, 51, 15, 7, 0, 9], CodeAddress(0), ProgramByteLimit(8),
      JumpCountLimit(0)).value
  decoded = instruction(owner, CodeAddress(1)) # A genuine owner never turns an operand byte into an executable result.
elif origin == "valid":
  var owner = decodeProgram([0'u8, 0, 4, 51, 15, 7, 0, 9], CodeAddress(0), ProgramByteLimit(8),
      JumpCountLimit(0)).value
  decoded = instruction(owner, CodeAddress(0))
  let retained = instructionRegisters(decoded)
  owner = default(Program)
  var copied = decoded.value
  copied.a = RegisterIndex(255)
  copied.b = RegisterIndex(255)
  copied.d = RegisterIndex(255)
  assert retained.aIndex == 12 and retained.bIndex == 0 and retained.dIndex == 0
  assert instructionRegisters(decoded).aIndex == 12 # Neither the released source handle nor mutable raw operands can rebind these scalar facts.
else:
  assert origin == "default" # Unknown modes cannot satisfy a selected contract-failure check.
if origin != "valid":
  discard instructionRegisters(decoded)
