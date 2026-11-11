# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Render source-decoded memory-loop controls and retain exact canonical machine bytes.

import std/[assertions, envvars, strutils, syncio]
import ../../src/pvm/program
import ../../src/pvm/internal/native_ir
when defined(pvmX86Jit):
  import ../../src/pvm/internal/x86_jit
else:
  import ../../src/pvm/internal/arm64_jit

proc operation(opcode, lanes: byte, operand: uint32 = 0): NativeOperation =
  ## Bind bounded roles through the real decoder before constructing copied control operations.
  let wire = [0'u8, 0, 7, opcode, lanes, byte(operand and 255), byte((operand shr 8) and 255),
    byte((operand shr 16) and 255), byte(operand shr 24), 0, 0x41]
  let owner = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert owner.error == ProgramError.None
  let decoded = instruction(owner.value, CodeAddress(0))
  assert decoded.error == ProgramError.None
  NativeOperation(opcode: opcode, slots: instructionRegisters(decoded),
    immediate: uint64(decoded.value.x))

proc encoded(operations: openArray[NativeOperation]): seq[byte] =
  ## Preserve byte order explicitly for the pure ARM encoding and use the native x86 byte vector.
  when defined(pvmX86Jit):
    result = x86MixedLoopInstructions(operations)
  else:
    result = @[]
    for word in armMixedLoopInstructions(operations):
      for lane in 0..<4:
        result.add(byte((word shr (lane*8)) and 255'u32))

proc report(opcode: byte, bytes: openArray[byte]) =
  ## Retain each exact machine image for independent identity and disassembly checks.
  assert bytes.len > 0
  var hex = ""
  for value in bytes:
    hex.add(toHex(int(value), 2))
  echo "MEMORY_LOOP_ENCODING,", opcode, ",", bytes.len, ",", hex

let canonicalOnly = getEnv("RAGNAROK_PVM_CANONICAL_ONLY")
assert canonicalOnly in ["", "1"]
if canonicalOnly.len == 0:
  # The new signed terminal admits a read-only body and refuses unsupported body variants.
  let original = [operation(129, 0xc6), operation(200, 0xab, 11),
    operation(149, 0xcc, 4), operation(173, 0x67)]
  let image = encoded(original)
  assert image.len > 0
  var invalid = original
  invalid[1] = operation(120, 0x50)
  assert encoded(invalid).len == 0
  invalid = original
  invalid[0] = operation(149, 0xcc, 4)
  assert encoded(invalid).len == 0
  invalid = original
  invalid[3] = operation(171, 0x67)
  assert encoded(invalid).len == 0
  report(173, image)

let canonical = [operation(152, 0x57, 4), operation(210, 0x97, 7),
  operation(58, 10, 17470384), operation(139, 0x58, 26), operation(212, 0x87, 7),
  operation(58, 8, 17470376), operation(200, 0xa7, 7), operation(124, 0x77),
  operation(200, 0x87, 7), operation(124, 0x77), operation(149, 0xb8, 1),
  operation(120, 0xb7), operation(190, 0x25, 5), operation(100, 0x8b), operation(171, 0x38)]
report(171, encoded(canonical))
