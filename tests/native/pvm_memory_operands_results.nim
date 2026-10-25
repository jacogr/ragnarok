# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default decode results grant no memory facts; genuine scalar facts survive raw-copy changes and owner release.
import std/[assertions, cmdline]
import ../../src/pvm/program
let origin = paramStr(1)
var decoded = default(ProgramResult[Instruction])
if origin == "invalid":
  decoded = instruction(default(Program), CodeAddress(0))
elif origin == "unmarked":
  let owner = decodeProgram([0'u8, 0, 4, 52, 15, 7, 0, 9], CodeAddress(0), ProgramByteLimit(8),
      JumpCountLimit(0)).value
  decoded = instruction(owner, CodeAddress(1)) # Operand bytes never authorize a memory-fact query.
elif origin == "valid":
  var owner = decodeProgram([0'u8, 0, 4, 52, 15, 7, 0, 9], CodeAddress(0), ProgramByteLimit(8),
      JumpCountLimit(0)).value
  decoded = instruction(owner, CodeAddress(0))
  let retained = instructionMemoryOperands(decoded)
  owner = default(Program)
  var copied = decoded.value
  copied.opcode = 123
  copied.x = Immediate(0)
  assert retained.width == 1 and retained.isLoad and not retained.isSigned
  assert retained.base == MemoryBase.None and not retained.usesImmediate
  assert instructionMemoryOperands(decoded).width ==
      1 # Neither mutable operand copies nor owner retirement rebind genuine facts.
else:
  assert origin == "default" # Unknown modes cannot satisfy a selected contract-failure check.
if origin != "valid":
  discard instructionMemoryOperands(decoded)
