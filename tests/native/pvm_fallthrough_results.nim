# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Missing decoded results grant no fallthrough fact; a genuine success is the runtime positive control.
import std/[assertions, cmdline]
import ../../src/pvm/program
proc runFailureProbe*(origin: string) =
  ## Execute exactly one argv-selected probe; the caller retains separate process isolation.
  var decoded = default(ProgramResult[Instruction])
  if origin == "invalid":
    decoded = instruction(default(Program), CodeAddress(0))
  elif origin == "valid":
    # Independent load followed by trap proves both success facts without any program storage access.
    let owner = decodeProgram([0'u8, 0, 4, 51, 0, 7, 0, 9], CodeAddress(0), ProgramByteLimit(8),
        JumpCountLimit(0)).value
    decoded = instruction(owner, CodeAddress(0))
    assert decoded.error == ProgramError.None and instructionHasFallthrough(decoded)
    assert not instructionHasFallthrough(instruction(owner, CodeAddress(3)))
  else:
    assert origin == "default"
  if origin != "valid":
    discard instructionHasFallthrough(decoded) # Every failed selection must terminate at the success-only precondition.

when isMainModule:
  # Standalone reproduction keeps its original command-line selection.
  runFailureProbe(paramStr(1))
