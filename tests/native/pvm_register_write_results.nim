# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime-selected failed scalar arithmetic results must reject both payload accessors; valid mode is the positive control.
import std/[assertions, cmdline, syncio]
import ../../src/pvm/[program, machine, registers]
let origin = paramStr(1)
let member = paramStr(2)
var written = default(RegisterWriteResult)
if origin == "invalid":
  written = evaluateRegisterWrite(default(ProgramResult[Instruction]), default(RegisterFile))
elif origin == "unsupported":
  # A valid trap grants no arithmetic write, even though its program owner exists.
  let owner = decodeProgram([0'u8, 0, 1, 0, 1], CodeAddress(0), ProgramByteLimit(5), JumpCountLimit(0)).value
  written = evaluateRegisterWrite(instruction(owner, CodeAddress(0)), default(RegisterFile))
elif origin == "valid":
  # Independently authored load_imm A0,7 followed by trap proves successful payload access remains usable.
  let owner = decodeProgram([0'u8, 0, 4, 51, 0, 7, 0, 9], CodeAddress(0), ProgramByteLimit(8),
      JumpCountLimit(0)).value
  written = evaluateRegisterWrite(instruction(owner, CodeAddress(0)), default(RegisterFile))
else:
  assert origin == "default" # Unknown modes must fail before any result interpretation.
if origin == "valid":
  assert written.error == RegisterError.None
  assert byte(written.destination) == 0 and uint64(written.writeValue) == 7
elif member == "destination":
  discard written.destination # Every failed origin must terminate at the accessor's success precondition.
elif member == "value":
  discard written.writeValue
else:
  quit(2) # Missing or unknown selectors cannot satisfy a contract-failure diagnostic.
