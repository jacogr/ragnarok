# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A relocated literal bitmap loop shared by execution and lowering refusal witnesses.

import std/assertions
import ../../src/pvm/program

proc bitmapOwner*(): Program =
  ## Entry PC4 falls into the scan at PC5. PCs51,53,58 halt, reset and trap respectively.
  let wire = [0'u8, 0, 59, 0, 0, 0, 0, 1,
    149, 0xbb, 1, 200, 0xc5, 5, 170, 0xb7, 40,
    132, 0xbc, 1, 81, 0x0c, 244,
    152, 0xbc, 1, 174, 0xac, 30,
    152, 0xb6, 7, 174, 0x96, 29,
    151, 0x66, 3, 200, 0x86, 6, 130, 0x66, 133, 0x66, 255,
    208, 0xc6, 12, 132, 0xcc, 1, 40, 212,
    50, 0, 51, 4, 42, 50, 0, 0,
    63, 73, 146, 36, 73, 73, 42, 5]
  let decoded = decodeJamProgram(wire, CodeAddress(4), ProgramByteLimit(128), JumpCountLimit(0))
  assert decoded.error == ProgramError.None, "bitmap wire decodes"
  decoded.value
