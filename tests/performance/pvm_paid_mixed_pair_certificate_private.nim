# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

import std/[assertions, syncio]
import ../../src/codec/natural
import ../../src/pvm/program
import ../../src/pvm/internal/handler_stream
import ../support/pvm_mixed_loop_source

const
  base = 62'u64*4096
  wordAddress = 64'u64*4096-2
  readBase = 66'u64*4096

proc emitAbsolute(opcode, register: byte, address: uint64): array[6, byte] =
  [opcode, register, byte(address and 255), byte((address shr 8) and 255),
    byte((address shr 16) and 255), byte((address shr 24) and 255)]

proc paidProgram(): Program =
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  template emit(op: openArray[byte]) =
    starts.add(code.len)
    for item in op: code.add(item)
  emit([2'u8]) # Folded first source fact.
  emit([124'u8, 0x61, 0]) # Load U8 R1,[R6].
  emit([120'u8, 0x50, 0]) # Store U8 [R5],R0.
  emit([2'u8]) # Folded interior source fact.
  emit([130'u8, 0x92, 0]) # Load U64 R2,[R9].
  emit(emitAbsolute(57, 3, base)) # Load S32 R3,[base], observing the earlier byte write.
  emit([149'u8, 0x99, 4]) # R9 advances into a crossing on the next visit.
  emit(emitAbsolute(61, 3, wordAddress))
  emit([149'u8, 0x55, 1]) # R5 advances to the BNE bound.
  let displacement = cast[uint32](-int32(code.len))
  emit([171'u8, 0xc5, byte(displacement and 255), byte((displacement shr 8) and 255),
    byte((displacement shr 16) and 255), byte(displacement shr 24)])
  emit([0'u8])
  var wire = @[0'u8, 0]
  let length = encode(JamNatural(uint64(code.len)))
  for index in 0..<length.len: wire.add(length.bytes[index])
  for item in code: wire.add(item)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for item in mask: wire.add(item)
  let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(1024), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  decoded.value

runMixedLoopSource()
witnessFlatPaidMixedLoop(paidProgram(), 0, base, wordAddress, readBase)
echo "MIXED_PAID_CERTIFICATE_OK"
