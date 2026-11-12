# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## JamV1 decoding translated from pinned PolkaVM common/program.rs. Packed lookup
## tables preserve read_args handling of truncated/overlong immediates. Chunks include
## bytes after the next instruction boundary, as upstream does; length controls decoding.
## See PORTING.md for source attribution. No production decoder is imported.

import std/[assertions, bitops]
import ./opcodes
export opcodes

type
  Chunk* = array[2, uint64]
    ## Little-endian u128 window, zero-padded only at the end of code.
  Instruction* = object
    ## Source operands; raw registers remain unnormalized until used.
    opcode*: Opcode
    a*, b*, c*, x*, y*: uint32
    wide*: uint64
  ParsedInstruction* = object
    ## Source PC/continuation accompany the instruction without owning bytes.
    instruction*: Instruction
    offset*, nextOffset*: uint32
  InstructionCursor* = object
    ## Iterator state; pending invalid instructions are yielded once.
    offset, invalidOffset: uint32
    pendingInvalid, bounded, done: bool

proc buildTable(offset: int): array[256, uint32] =
  ## LookupTable::build clamps each immediate length separately.
  result = default(array[256, uint32])
  for skip in 0..31:
    for auxiliary in 0..7:
      let firstLength = min(4, auxiliary)
      let secondLength = min(4, max(0, skip-firstLength-offset))
      result[skip or (auxiliary shl 5)] = uint32(32-firstLength*8) or
        (uint32(firstLength*8) shl 6) or (uint32(32-secondLength*8) shl 12)

const
  table2 = buildTable(2)
  table3 = buildTable(3)

proc chunk*(code: openArray[byte], offset: uint32): Chunk =
  ## load_chunk uses an unaligned bulk load, zero-filling only a short code tail.
  result = default(Chunk)
  let at = min(int(offset), code.len)
  let length = min(16, code.len-at)
  if length != 0:
    copyMem(addr result[0], unsafeAddr code[at], length)

proc shifted(value: Chunk, bits: int): uint64 {.inline.} =
  ## Extract the requested u64 from a source u128 without a foreign arithmetic call.
  assert bits > 0 and bits < 64
  (value[0] shr bits) or (value[1] shl (64-bits))

proc signCut(value, cut: uint32): uint32 {.inline.} =
  ## Source u64-left/i32-right sequence makes cut=32 return zero.
  let truncated = uint32(uint64(value) shl cut)
  cast[uint32](cast[int32](truncated) shr (cut and 31))

proc register*(raw: uint32): int {.inline.} =
  ## RawReg::get masks to a nibble and clamps encodings 13..15 to A5.
  int(min(raw and 15, 12'u32))

proc decode*(value: Chunk, offset, length: uint32): Instruction =
  ## Translate read_args with EXT=false, the explicitly selected JamV1 ISA.
  assert length >= 1 and length <= 25
  let raw = byte(value[0])
  let body = shifted(value, 8)
  let form = operandFormat(raw)
  result = Instruction(opcode: opcode(raw))
  case form
  of OperandFormat.fmtInvalid, OperandFormat.fmtNone:
    discard
  of OperandFormat.fmtImm, OperandFormat.fmtOffset:
    result.x = signCut(uint32(body), 32-min(4'u32, length-1)*8)
    if form == OperandFormat.fmtOffset: result.x += offset
  of OperandFormat.fmtImm2, OperandFormat.fmtRegImm2, OperandFormat.fmtRegImmOffset:
    let auxiliary = if form == OperandFormat.fmtImm2: uint32(body) else: (uint32(body) shr 4)
    let packed = table2[int((length and 31) or ((auxiliary and 7) shl 5))]
    let operands = shifted(value, 16)
    if form != OperandFormat.fmtImm2: result.a = uint32(body)
    result.x = signCut(uint32(operands), packed and 63)
    result.y = signCut(uint32(operands shr ((packed shr 6) and 63)), (packed shr 12) and 63)
    if form == OperandFormat.fmtRegImmOffset: result.y += offset
  of OperandFormat.fmtRegImm, OperandFormat.fmtRegs2Imm, OperandFormat.fmtRegs2Offset:
    result.a = uint32(body)
    if form != OperandFormat.fmtRegImm: result.b = (uint32(body) shr 4)
    let packed = table2[int(length and 31)]
    result.x = signCut(uint32(shifted(value, 16)), (packed shr 12) and 63)
    if form == OperandFormat.fmtRegs2Offset: result.x += offset
  of OperandFormat.fmtRegs2Imm2:
    result.a = uint32(body)
    result.b = (uint32(body) shr 4)
    let packed = table3[int((length and 31) or (((uint32(body) shr 8) and 7) shl 5))]
    let operands = shifted(value, 24)
    result.x = signCut(uint32(operands), packed and 63)
    result.y = signCut(uint32(operands shr ((packed shr 6) and 63)), (packed shr 12) and 63)
  of OperandFormat.fmtRegImm64:
    result.a = uint32(body)
    result.wide = shifted(value, 16)
  of OperandFormat.fmtRegs2:
    result.a = uint32(body)
    result.b = (uint32(body) shr 4)
  of OperandFormat.fmtRegs3:
    result.a = (uint32(body) shr 8)
    result.b = uint32(body)
    result.c = (uint32(body) shr 4)

proc startsBlock*(op: Opcode): bool =
  ## Opcode::starts_new_basic_block plus invalid's effective trap behavior.
  op in {Opcode.op_invalid, Opcode.op_trap, Opcode.op_fallthrough, Opcode.op_jump,
    Opcode.op_jump_indirect, Opcode.op_load_imm_and_jump, Opcode.op_load_imm_and_jump_indirect,
    Opcode.op_branch_eq, Opcode.op_branch_not_eq, Opcode.op_branch_less_unsigned,
    Opcode.op_branch_less_signed, Opcode.op_branch_greater_or_equal_unsigned,
    Opcode.op_branch_greater_or_equal_signed, Opcode.op_branch_eq_imm,
    Opcode.op_branch_not_eq_imm, Opcode.op_branch_less_unsigned_imm,
    Opcode.op_branch_less_signed_imm, Opcode.op_branch_greater_or_equal_unsigned_imm,
    Opcode.op_branch_greater_or_equal_signed_imm, Opcode.op_branch_less_or_equal_unsigned_imm,
    Opcode.op_branch_less_or_equal_signed_imm, Opcode.op_branch_greater_unsigned_imm,
    Opcode.op_branch_greater_signed_imm}

proc fallsThrough(op: Opcode): bool =
  ## Invalid raw opcodes use the source unwrap_or(trap) terminal classification.
  op notin {Opcode.op_invalid, Opcode.op_trap, Opcode.op_jump, Opcode.op_jump_indirect,
    Opcode.op_load_imm_and_jump, Opcode.op_load_imm_and_jump_indirect}

proc instructionStart*(mask: openArray[byte], codeLength: int, offset: uint32): bool =
  ## Validated masks have zero padding beyond the code extent.
  let index = int(offset shr 3)
  index < mask.len and int(offset) <= codeLength and ((mask[index] shr (offset and 7)) and 1) != 0

proc findNext(mask: openArray[byte], codeLength: int, offset: uint32): uint32 {.noinline.} =
  ## Cold unbounded scan skips complete zero mask bytes.
  var position = offset
  while int(position shr 3) < mask.len:
    let shift = position and 7
    let bits = mask[int(position shr 3)] shr shift
    if bits == 0: position += 8-shift
    else:
      position += uint32(trailingZeroBits(bits))
      break
  min(uint32(codeLength), position)

proc initCursor*(mask: openArray[byte], codeLength: int, offset: uint32,
    bounded: bool): InstructionCursor =
  ## Instructions::new_impl includes the UINT32_MAX bounded empty iterator.
  assert codeLength <= int(high(int32)) and mask.len == (codeLength+7) div 8
  result = InstructionCursor(offset: offset, bounded: bounded)
  if not instructionStart(mask, codeLength, offset):
    result.done = bounded
    if bounded and offset == high(uint32): return
    result.pendingInvalid = true
    result.invalidOffset = offset
    result.offset = if bounded: min(offset+1, uint32(codeLength)) else: findNext(mask, codeLength, offset)

proc next*(cursor: var InstructionCursor, code, mask: openArray[byte],
    parsed: var ParsedInstruction): bool =
  ## Instructions::next_legacy preserves the source fast/slow bitmask split.
  if cursor.pendingInvalid:
    cursor.pendingInvalid = false
    parsed = ParsedInstruction(instruction: Instruction(opcode: Opcode.op_invalid),
      offset: cursor.invalidOffset, nextOffset: cursor.offset)
    return true
  if cursor.done or int(cursor.offset) >= code.len: return false
  let offset = cursor.offset
  var skip = 0'u32
  var invalidNext = false
  if int(offset)+32 <= code.len:
    let index = int((offset+1) shr 3)
    assert index+4 <= mask.len
    var bits = 0'u32
    copyMem(addr bits, unsafeAddr mask[index], 4)
    bits = (bits shr ((offset+1) and 7)) or (1'u32 shl 24)
    skip = uint32(trailingZeroBits(bits))
    invalidNext = skip == 24 and not instructionStart(mask, code.len, offset+skip+1)
  else:
    let origin = int(offset)+1
    var position = origin
    invalidNext = true
    while position shr 3 < mask.len:
      let shift = position and 7
      let bits = mask[position shr 3] shr shift
      if bits == 0:
        position += 8-shift
        if position-origin < 24: continue
      else:
        position += trailingZeroBits(bits)
        invalidNext = position >= code.len or position-origin > 24
      break
    skip = uint32(min(24, min(position, code.len)-origin))
  let instruction = decode(chunk(code, offset), offset, skip+1)
  let following = offset+skip+1
  if invalidNext and int(following) >= code.len and not fallsThrough(instruction.opcode):
    invalidNext = false
  parsed = ParsedInstruction(instruction: instruction, offset: offset, nextOffset: following)
  cursor.offset = following
  if invalidNext:
    cursor.pendingInvalid = true
    cursor.invalidOffset = following
    if int(following) == code.len: cursor.offset = uint32(code.len)+1
    elif cursor.bounded:
      cursor.done = true
      cursor.offset = uint32(code.len)
    else: cursor.offset = findNext(mask, code.len, following)
  true

proc validJump*(code, mask: openArray[byte], offset: uint32): bool =
  ## Previous-instruction scan is limited to 24 padding bytes, as in the source.
  if int(offset) >= code.len: return false
  var bits = uint64(mask[int(offset shr 3)]) shl 56
  for previous in 1..4:
    if offset >= uint32(previous*8):
      bits = bits or (uint64(mask[int(offset shr 3)-previous]) shl (56-previous*8))
  bits = (bits shl (8-(offset and 7))) shr 1
  let skip = leadingZeroBits(bits)-1
  # is_instruction_start_legacy also admits PC zero and the implicit trap after 24 padding bytes.
  if offset != 0 and not instructionStart(mask, code.len, offset) and skip != 24: return false
  if skip > 24: return true
  let previous = offset-uint32(skip)-1
  startsBlock(opcode(code[int(previous)]))

proc previousSkip(mask: openArray[byte], offset: uint32): int =
  ## Source bounded reverse scan; values above 24 mean no preceding instruction.
  var bits = uint64(mask[int(offset shr 3)]) shl 56
  for previous in 1..4:
    if offset >= uint32(previous * 8):
      bits = bits or (uint64(mask[int(offset shr 3) - previous]) shl (56 - previous * 8))
  bits = (bits shl (8 - (offset and 7))) shr 1
  leadingZeroBits(bits) - 1

proc enclosingBlock*(code, mask: openArray[byte], pc: uint32): uint32 =
  ## Legacy find_start_of_basic_block, returning UINT32_MAX for invalid entry positions.
  if int(pc) >= code.len: return high(uint32)
  var offset = pc
  var skip = previousSkip(mask, offset)
  if offset != 0 and not instructionStart(mask, code.len, offset) and skip != 24:
    return high(uint32)
  while skip <= 24:
    let previous = offset - uint32(skip) - 1
    if opcode(code[int(previous)]).startsBlock: break
    offset = previous
    skip = previousSkip(mask, offset)
  offset

proc validateCode*(code, mask: openArray[byte]): uint32 =
  ## JamV1 Module::from_blob validates the complete bounded stream before instantiation.
  var cursor = initCursor(mask, code.len, 0, true)
  var parsed = default(ParsedInstruction)
  while cursor.next(code, mask, parsed):
    if parsed.instruction.opcode == Opcode.op_invalid: return parsed.offset
  high(uint32)
