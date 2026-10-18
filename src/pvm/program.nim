# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 program deblob and operand decoding; see spec/pvm-program.md. Input is borrowed
## during validation, then copied into private acyclic ARC storage.
##
## Exposes Program snapshots and nominal address/index/limit types, decodeProgram,
## instruction/jump lookup and basic-block queries.

import ../codec/natural

type
  # Byte-addressed instruction counter, also used for copied dynamic jump targets.
  CodeAddress* = distinct uint64
  # A table ordinal is deliberately not an instruction counter or dynamic jump address.
  JumpIndex* = distinct uint64
  # Caller policy is separate from consensus admissibility.
  ProgramByteLimit* = distinct uint64
  # Logical table count policy also bounds zero-width encodings.
  JumpCountLimit* = distinct uint64
  # Register identifiers and register-width immediate bit patterns are separate domains.
  RegisterIndex* = distinct byte
  # Sign-extended values preserve their unsigned 64-bit register representation.
  Immediate* = distinct uint64
  # All failures carry only a reason; the default is never successful.
  ProgramError* {.pure.} = enum
    Uninitialized, None, Truncated, NonCanonical, LimitExceeded, InvalidJumpValue,
    InvalidProgram, InvalidInstruction, InvalidOwner, InvalidIndex, TrailingBytes
  # Private variants prevent callers from forging success or extracting failed payloads.
  ProgramResult*[T] = object
    case status: ProgramError
    of None:
      # Only fully validated values are published.
      completed: T
    else:
      # No partial owner, cursor or value escapes a failure.
      discard
  # A single immutable byte allocation owns code, bitmap and compressed table together.
  ProgramData = ref object
    bytes: seq[byte]
    codeOffset, codeLength, maskOffset, jumpOffset, jumpWidth: int
    jumps: uint64
  # Copyable ARC handle; no API exports its backing bytes or mutable storage.
  Program* = object
    data: nil ProgramData
  # Each shape follows one operand equation in the pinned instruction tables.
  OperandShape* {.pure.} = enum
    NoArguments, OneImmediate, ExtendedImmediate, TwoImmediates, OneOffset,
    RegisterImmediate, RegisterTwoImmediates, RegisterImmediateOffset, TwoRegisters,
    TwoRegistersImmediate, TwoRegistersOffset, TwoRegistersTwoImmediates, ThreeRegisters
  # Copied decoded operands use the GP names A/B/D and X/Y; unused fields are zero.
  # Offsets remain signed displacements: resolving a target must not wrap a negative address.
  Instruction* = object
    address*: CodeAddress
    opcode*: byte
    shape*: OperandShape
    skip*: range[0..24]
    a*, b*, d*: RegisterIndex
    x*, y*: Immediate
    displacement*: int64

# Inspect status without exposing a mutable discriminator.
func error*[T](r: ProgramResult[T]): ProgramError = r.status
# Extract a copied value only after establishing complete success.
func value*[T](r: ProgramResult[T]): T {.inline, requires: r.status == ProgramError.None.} =
  r.completed

# Exact set U from the 0.8.0 instruction tables, including unlikely (2).
func validOpcode*(opcode: byte): bool =
  opcode in {0'u8..2'u8, 10'u8, 20'u8, 30'u8..33'u8, 40'u8, 50'u8..62'u8,
    70'u8..73'u8, 80'u8..90'u8, 100'u8..110'u8, 120'u8..161'u8,
    170'u8..175'u8, 180'u8, 190'u8..230'u8}

# Exact set T; a host call suspends execution but does not terminate a basic block.
func terminatesBlock*(opcode: byte): bool =
  opcode in {0'u8, 1'u8, 40'u8, 50'u8, 80'u8..90'u8, 170'u8..175'u8, 180'u8}

# Read a known in-range logical mask bit; callers establish the extent first.
func marked(bytes: openArray[byte], maskOffset, index: int): bool =
  (bytes[maskOffset + index div 8] and (1'u8 shl (index mod 8))) != 0

# Infinite one-bit suffix and the 24-byte cap define skip even at the final instruction.
func distance(bytes: openArray[byte], maskOffset, length, index: int): range[0..24] =
  result = 0
  # Subtraction keeps the boundary check safe without constructing an overflowing endpoint.
  while result < 24 and result < length - index - 1:
    # A set bit ends the operand region; unset bytes extend it by one.
    if marked(bytes, maskOffset, index + 1 + result): break
    inc result

# Decode canonical framing, check every extent/value before allocation, then capture one owned copy.
# entry must name a marked valid opcode; jump targets are checked only when executed, not here.
proc decodeProgram*(input: openArray[byte], entry: CodeAddress,
    byteLimit: ProgramByteLimit, jumpLimit: JumpCountLimit): ProgramResult[Program] =
  # Bound even a fully present input before scanning or copying it.
  if uint64(input.len) > uint64(byteLimit):
    return ProgramResult[Program](status: ProgramError.LimitExceeded)
  let count = natural.decode(input)
  # A failed natural publishes neither its value nor consumed extent.
  if not count.ok:
    return ProgramResult[Program](status: (if count.error == natural.truncated:
      ProgramError.Truncated else: ProgramError.NonCanonical))
  let jumps = uint64(count.value)
  # Zero-width tables also need a logical count ceiling despite consuming no payload bytes.
  if jumps > uint64(jumpLimit): return ProgramResult[Program](status: ProgramError.LimitExceeded)
  var cursor = int(count.consumed)
  # The width is an independent one-byte field, including widths zero and above eight.
  if cursor == input.len: return ProgramResult[Program](status: ProgramError.Truncated)
  let width = int(input[cursor])
  inc cursor
  let codeCount = natural.decode(input.toOpenArray(cursor, input.len - 1))
  # Canonical naturals give a unique framing; overlong lengths are not alternate formats.
  if not codeCount.ok:
    return ProgramResult[Program](status: (if codeCount.error == natural.truncated:
      ProgramError.Truncated else: ProgramError.NonCanonical))
  cursor += int(codeCount.consumed)
  let codeSize = uint64(codeCount.value)
  let jumpOffset = cursor
  # Division proves the product fits both the supplied buffer and host indexing.
  if width != 0 and jumps > uint64((input.len - cursor) div width):
    return ProgramResult[Program](status: ProgramError.Truncated)
  let tableBytes = (if width == 0: 0 else: int(jumps) * width)
  cursor += tableBytes
  # Check code bytes before narrowing the untrusted natural to a host integer.
  if codeSize > uint64(input.len - cursor):
    return ProgramResult[Program](status: ProgramError.Truncated)
  let codeLength = int(codeSize)
  let codeOffset = cursor
  cursor += codeLength
  let maskOffset = cursor
  let maskBytes = codeLength div 8 + int(codeLength mod 8 != 0)
  # The complete bitmap is required; extra bytes cannot silently become a second program.
  if maskBytes > input.len - cursor: return ProgramResult[Program](status: ProgramError.Truncated)
  cursor += maskBytes
  # deblob consumes exactly one complete encoding.
  if cursor != input.len: return ProgramResult[Program](status: ProgramError.TrailingBytes)
  # Unused high bits must be zero to be in the image of the bitstring encoder.
  if codeLength mod 8 != 0 and (input[cursor - 1] shr (codeLength mod 8)) != 0:
    return ProgramResult[Program](status: ProgramError.NonCanonical)
  # E_z allows widths beyond eight, but a table element must still fit a 64-bit PVM register.
  if width > 8:
    var position = jumpOffset
    # Each step consumes a present table record, so this work is bounded by the input extent.
    while position < codeOffset:
      # High zero bytes are valid fixed-width padding; nonzero bytes exceed the register domain.
      for highByte in 8..<width:
        # Reject the first nonzero high byte without constructing an oversized integer.
        if input[position + highByte] != 0:
          return ProgramResult[Program](status: ProgramError.InvalidJumpValue)
      position += width
  # The empty program cannot satisfy v_inst at any entry point.
  if codeLength == 0: return ProgramResult[Program](status: ProgramError.InvalidProgram)
  var pc = 0
  # Iterative v_blob avoids recursion proportional to untrusted program length.
  while pc < codeLength:
    # Every traversed instruction must begin at a set mask bit and have an opcode in U.
    if not marked(input, maskOffset, pc) or not validOpcode(input[codeOffset + pc]):
      return ProgramResult[Program](status: ProgramError.InvalidProgram)
    let step = 1 + int(distance(input, maskOffset, codeLength, pc))
    # The final instruction must belong to T, even when it carries operand bytes.
    if step == codeLength - pc and not terminatesBlock(input[codeOffset + pc]):
      return ProgramResult[Program](status: ProgramError.InvalidProgram)
    pc += step
  # Validate entry without narrowing it until the code extent proves the conversion safe.
  if uint64(entry) >= codeSize:
    return ProgramResult[Program](status: ProgramError.InvalidInstruction)
  # An in-range operand byte is not a valid entry instruction.
  if not marked(input, maskOffset, int(uint64(entry))):
    return ProgramResult[Program](status: ProgramError.InvalidInstruction)
  var owned = newSeq[byte](input.len)
  # Copy after full validation; callers may mutate or release their input on return.
  for i in 0..<input.len: owned[i] = input[i]
  ProgramResult[Program](status: ProgramError.None, completed: Program(data: ProgramData(
    bytes: owned, codeOffset: codeOffset, codeLength: codeLength, maskOffset: maskOffset,
    jumpOffset: jumpOffset, jumpWidth: width, jumps: jumps)))

# Return logical code size without publishing backing storage; default handles are typed failures.
proc codeLength*(program: Program): ProgramResult[uint64] =
  # A default handle has no validated storage to inspect.
  if program.data == nil: return ProgramResult[uint64](status: ProgramError.InvalidOwner)
  ProgramResult[uint64](status: ProgramError.None, completed: uint64(program.data.codeLength))

# Read a table entry by ordinal, including implicit zero values in a zero-width table.
proc jumpTarget*(program: Program, index: JumpIndex): ProgramResult[CodeAddress] =
  # A default handle has no validated storage to inspect.
  if program.data == nil: return ProgramResult[CodeAddress](status: ProgramError.InvalidOwner)
  let data = program.data
  # Table indexing uses logical count, which may exceed host int for width zero.
  if uint64(index) >= data.jumps: return ProgramResult[CodeAddress](
      status: ProgramError.InvalidIndex)
  var target = 0'u64
  # Zero-width entries require no host-index conversion, even for very large logical ordinals.
  if data.jumpWidth != 0:
    let offset = data.jumpOffset + int(uint64(index)) * data.jumpWidth
    # Validation already proved all bytes above the register width are zero.
    for i in 0..<min(8, data.jumpWidth):
      target = target or (uint64(data.bytes[offset + i]) shl (8 * i))
  ProgramResult[CodeAddress](status: ProgramError.None, completed: CodeAddress(target))

# Read the GP infinite zero suffix, including operands that cross another marked instruction.
func codeByte(data: ProgramData, index: uint64): byte =
  # The suffix is semantic zero padding, not an out-of-bounds memory read.
  if index >= uint64(data.codeLength): return 0
  data.bytes[data.codeOffset + int(index)]

# Fixed-width little endian operand read; at most eight bytes and no shift by 64.
func unsignedOperand(data: ProgramData, start: uint64, width: int): uint64 =
  result = 0
  # Width and start come from bounded operand equations, never unvalidated blob lengths.
  for i in 0..<width: result = result or (uint64(codeByte(data, start + uint64(i))) shl (8 * i))

# Sign extension is expressed in unsigned bits, avoiding signed conversion overflow.
func extended(data: ProgramData, start: uint64, width: int): uint64 =
  result = unsignedOperand(data, start, width)
  # Empty immediates are zero and full-width immediates need no extension.
  if width > 0 and width < 8 and (result and (1'u64 shl (8 * width - 1))) != 0:
    result = result or (high(uint64) shl (8 * width))

# Signed offsets are at most four bytes; subtraction in int64 preserves negative destinations.
func offsetOperand(data: ProgramData, start: uint64, width: int): int64 =
  let raw = unsignedOperand(data, start, width)
  result = int64(raw)
  # Unlike register immediates, offsets are mathematical signed displacements, not wrapped PCs.
  if width > 0 and (raw and (1'u64 shl (width * 8 - 1))) != 0:
    result -= 1'i64 shl (width * 8)

# Copy a decoded instruction; invalid addresses and default handles never yield operands.
proc instruction*(program: Program, address: CodeAddress): ProgramResult[Instruction] =
  # A default handle has no validated storage to inspect.
  if program.data == nil: return ProgramResult[Instruction](status: ProgramError.InvalidOwner)
  let data = program.data
  let pc = uint64(address)
  # Check the address before narrowing it or accessing the mask.
  if pc >= uint64(data.codeLength):
    return ProgramResult[Instruction](status: ProgramError.InvalidInstruction)
  # Only marked bytes may be decoded as opcodes.
  if not marked(data.bytes, data.maskOffset, int(pc)):
    return ProgramResult[Instruction](status: ProgramError.InvalidInstruction)
  let opcode = codeByte(data, pc)
  let skip = distance(data.bytes, data.maskOffset, data.codeLength, int(pc))
  let first = int(codeByte(data, pc + 1))
  var item = Instruction(address: address, opcode: opcode, skip: skip,
    shape: OperandShape.NoArguments, a: RegisterIndex(0), b: RegisterIndex(0),
    d: RegisterIndex(0), x: Immediate(0), y: Immediate(0), displacement: 0)
  # Each branch corresponds to one complete operand shape in the pinned instruction tables.
  case opcode
  of 0..2:
    # Argument-free opcodes ignore any intervening unmarked bytes.
    discard
  of 10:
    # A single compact immediate uses up to four skipped bytes.
    item.shape = OperandShape.OneImmediate
    item.x = Immediate(extended(data, pc + 1, min(4, int(skip))))
  of 20:
    # Extended immediates always read eight bytes, independently of skip.
    item.shape = OperandShape.ExtendedImmediate
    item.a = RegisterIndex(min(12, first mod 16))
    item.x = Immediate(unsignedOperand(data, pc + 2, 8))
  of 30..33:
    # The prefix chooses X width; remaining skipped bytes choose Y width.
    item.shape = OperandShape.TwoImmediates
    let xlen = min(4, first mod 8)
    item.x = Immediate(extended(data, pc + 2, xlen))
    item.y = Immediate(extended(data, pc + 2 + uint64(xlen), min(4, max(0, int(skip) - xlen - 1))))
  of 40:
    # Preserve the signed displacement for subsequent checked static-target resolution.
    item.shape = OperandShape.OneOffset
    item.displacement = offsetOperand(data, pc + 1, min(4, int(skip)))
  of 50..62:
    # Register nibbles saturate at 12; they are not rejected or reduced modulo 13.
    item.shape = OperandShape.RegisterImmediate
    item.a = RegisterIndex(min(12, first mod 16))
    item.x = Immediate(extended(data, pc + 2, min(4, max(0, int(skip) - 1))))
  of 70..73, 80..90:
    # These groups share X and register decoding; Y is immediate or signed offset.
    item.a = RegisterIndex(min(12, first mod 16))
    let xlen = min(4, (first div 16) mod 8)
    let ylen = min(4, max(0, int(skip) - xlen - 1))
    item.x = Immediate(extended(data, pc + 2, xlen))
    if opcode <= 73:
      # Stores use two register-width immediate bit patterns.
      item.shape = OperandShape.RegisterTwoImmediates
      item.y = Immediate(extended(data, pc + 2 + uint64(xlen), ylen))
    else:
      # Static jumps and immediate branches use a signed second operand.
      item.shape = OperandShape.RegisterImmediateOffset
      item.displacement = offsetOperand(data, pc + 2 + uint64(xlen), ylen)
  of 100..110:
    # This group uniquely names the low nibble D and the high nibble A.
    item.shape = OperandShape.TwoRegisters
    item.d = RegisterIndex(min(12, first mod 16))
    item.a = RegisterIndex(min(12, first div 16))
  of 120..161, 170..175:
    # Both groups decode low A and high B; the last operand determines their shape.
    item.a = RegisterIndex(min(12, first mod 16))
    item.b = RegisterIndex(min(12, first div 16))
    let width = min(4, max(0, int(skip) - 1))
    if opcode <= 161:
      # Arithmetic and indirect memory instructions use a sign-extended immediate.
      item.shape = OperandShape.TwoRegistersImmediate
      item.x = Immediate(extended(data, pc + 2, width))
    else:
      # Register comparisons use a signed static branch displacement.
      item.shape = OperandShape.TwoRegistersOffset
      item.displacement = offsetOperand(data, pc + 2, width)
  of 180:
    # Dynamic load-and-jump has a second descriptor byte before its two immediates.
    item.shape = OperandShape.TwoRegistersTwoImmediates
    item.a = RegisterIndex(min(12, first mod 16))
    item.b = RegisterIndex(min(12, first div 16))
    let xlen = min(4, int(codeByte(data, pc + 2)) mod 8)
    item.x = Immediate(extended(data, pc + 3, xlen))
    item.y = Immediate(extended(data, pc + 3 + uint64(xlen), min(4, max(0, int(skip) - xlen - 2))))
  of 190..230:
    # The whole second operand byte, not just its low nibble, saturates to register D.
    item.shape = OperandShape.ThreeRegisters
    item.a = RegisterIndex(min(12, first mod 16))
    item.b = RegisterIndex(min(12, first div 16))
    item.d = RegisterIndex(min(12, int(codeByte(data, pc + 2))))
  else:
    # A valid owner cannot contain another marked opcode; retain an explicit failure alternative.
    return ProgramResult[Instruction](status: ProgramError.InvalidInstruction)
  ProgramResult[Instruction](status: ProgramError.None, completed: item)

# Membership in varpi uses a bounded backward search, since skip is at most 24.
proc basicBlockStart*(program: Program, address: CodeAddress): ProgramResult[bool] =
  # Establish ownership locally as well as through the instruction result.
  # A default handle has no validated storage to inspect.
  if program.data == nil: return ProgramResult[bool](status: ProgramError.InvalidOwner)
  let decoded = instruction(program, address)
  # Preserve address failures instead of treating invalid positions as ordinary block members.
  if decoded.error != ProgramError.None: return ProgramResult[bool](status: decoded.error)
  let pc = int(uint64(address))
  # The validated first instruction always begins a basic block.
  if pc == 0: return ProgramResult[bool](status: ProgramError.None, completed: true)
  let data = program.data
  var previous = pc - 1
  # The closest marked predecessor is the only instruction that could end at this boundary.
  while previous >= max(0, pc - 25):
    # A terminator immediately preceding this instruction creates the next basic block.
    if marked(data.bytes, data.maskOffset, previous):
      return ProgramResult[bool](status: ProgramError.None,
        completed: terminatesBlock(data.bytes[data.codeOffset + previous]))
    dec previous
  ProgramResult[bool](status: ProgramError.None, completed: false)
