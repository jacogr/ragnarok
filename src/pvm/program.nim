# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 program deblob and operand decoding; see spec/pvm-program.md. Input is borrowed
## during validation, then copied into private acyclic ARC storage.
##
## Exposes Program snapshots and nominal address/index/limit types, decodeProgram/decodeJamProgram,
## instruction/opcode/jump lookup, raw instruction-byte lookup with zero padding, and block-boundary
## and containing-block queries. Genuine instruction results additionally expose success-guarded
## instructionHasFallthrough/TargetStartsBlock and instructionRegisters/instructionMemoryOperands
## without publishing mutable validation metadata.

import ../codec/natural

const
  jamCodeBytes = 32'u64 * 1024 * 1024 # GP-PVM-007: pinned PolkaVM's instruction-byte ceiling.
  jamJumpEntries = 16'u64 * 1024 * 1024 # Declared entries are bounded before width-zero normalization.

type
  CodeAddress* = distinct uint64 ## Byte-addressed instruction counter, also used for copied dynamic jump targets.
  JumpIndex* = distinct uint64 ## A table ordinal is deliberately not an instruction counter or dynamic jump address.
  ProgramByteLimit* = distinct uint64 ## Caller policy is separate from consensus admissibility.
  JumpCountLimit* = distinct uint64 ## Logical table count policy also bounds zero-width encodings.
  RegisterIndex* = distinct byte ## Register identifiers and register-width immediate bit patterns are separate domains.
  Immediate* = distinct uint64 ## Sign-extended values preserve their unsigned 64-bit register representation.
  ProgramError* {.pure.} = enum ## All failures carry only a reason; the default is never successful.
    Uninitialized, None, Truncated, NonCanonical, LimitExceeded, InvalidJumpValue,
    InvalidProgram, InvalidInstruction, InvalidOwner, InvalidIndex, TrailingBytes
  ProgramResult*[T] = object ## Private variants prevent callers from forging success or extracting failed payloads.
    case status: ProgramError
    of None:
      # Only fully validated values are published.
      completed: T
    else:
      # No partial owner, cursor or value escapes a failure.
      discard
  # The private choice cannot be supplied accidentally through an existing raw decoder call.
  DecodeProfile {.pure.} = enum
    Paper, Jam
  # A single immutable byte allocation owns code, bitmap and compressed table together.
  ProgramData = ref object
    bytes: seq[byte]
    codeOffset, codeLength, maskOffset, jumpOffset, jumpWidth: int
    jumps: uint64
    profile: DecodeProfile
  Program* = object ## Copyable ARC handle; no API exports its backing bytes or mutable storage.
    data: nil ProgramData
  OperandShape* {.pure.} = enum ## Each shape follows one operand equation in the pinned instruction tables.
    NoArguments, OneImmediate, ExtendedImmediate, TwoImmediates, OneOffset,
    RegisterImmediate, RegisterTwoImmediates, RegisterImmediateOffset, TwoRegisters,
    TwoRegistersImmediate, TwoRegistersOffset, TwoRegistersTwoImmediates, ThreeRegisters
  RegisterSlots* = object ## Copied bounded host coordinates retain no program/machine owner; only genuine instruction queries bind them to operands.
    aSlot, bSlot, dSlot, writeSlot: range[0'u8..12'u8]
  MemoryBase* {.pure.} = enum ## A decoded memory address uses no register, original A or original B.
    None, A, B
  MemoryOperands* = object ## Copied scalar facts are derived once by the owner decoder; defaults describe no memory access.
    widthValue: byte
    loadingValue, signedValue: bool
    baseValue: MemoryBase
    immediateValue: bool
  Instruction* = object ## Copied decoded operands use the GP names A/B/D and X/Y; unused fields are zero.
 ## Offsets remain signed displacements: resolving a target must not wrap a negative address.
    address*: CodeAddress
    opcode*: byte
    shape*: OperandShape
    targetStartsBlock: bool # Owner-bound static control membership is never writable through extracted operands.
    memoryOperands: MemoryOperands # These five byte-sized facts occupy existing alignment padding before skip.
    skip*: range[0..24]
    a*, b*, d*: RegisterIndex
    fallthroughPresent: bool # Only the owner decoder grants this immutable v_blob-chain fact; copied operands cannot forge a tagged result.
    registerSlots: RegisterSlots # Saturated coordinates remain private facts of the captured operand decode.
    x*, y*: Immediate
    displacement*: int64

func error*[T](r: ProgramResult[T]): ProgramError =
  ## Inspect status without exposing a mutable discriminator.
  r.status
func value*[T](r: ProgramResult[T]): T {.inline, requires: r.status == ProgramError.None.} =
  ## Extract a copied value only after establishing complete success.
  r.completed

func instructionHasFallthrough*(decoded: ProgramResult[Instruction]): bool {.inline,
    requires: decoded.status == ProgramError.None.} =
  ## A genuine successful decode proves whether its sequential successor is executable in the same immutable program.
  ## Default/failed results grant no fact. Extracted mutable operand copies cannot change or rebind this capability.
  decoded.completed.fallthroughPresent

func instructionTargetStartsBlock*(decoded: ProgramResult[Instruction]): bool {.inline,
    requires: decoded.status == ProgramError.None.} =
  ## Report valid static control destination membership in the same immutable program; dynamic/noncontrol instructions report false.
  ## Invalid mathematical targets remain successful decodes with a false fact, preserving gas-first guest panic ordering.
  decoded.completed.targetStartsBlock

func aIndex*(slots: RegisterSlots): range[0..12] {.inline.} =
  ## Widen a bounded scalar coordinate without losing its array-index proof.
  int(slots.aSlot)
func bIndex*(slots: RegisterSlots): range[0..12] {.inline.} =
  ## Read the second bounded coordinate; default copied coordinates are ordinary zero indices.
  int(slots.bSlot)
func dIndex*(slots: RegisterSlots): range[0..12] {.inline.} =
  ## Read the decoded destination coordinate without exposing mutable backing.
  int(slots.dSlot)
func destinationIndex*(slots: RegisterSlots): range[0..12] {.inline.} =
  ## Read the arithmetic destination; non-register instructions/default copied coordinates report zero, never a write authorization.
  int(slots.writeSlot)
func instructionRegisters*(decoded: ProgramResult[Instruction]): RegisterSlots {.inline,
    requires: decoded.status == ProgramError.None.} =
  ## Only a genuine successful decode binds A/B/D and arithmetic-destination coordinates to immutable operand values.
  decoded.completed.registerSlots
func instructionMemoryOperands*(decoded: ProgramResult[Instruction]): MemoryOperands {.inline,
    requires: decoded.status == ProgramError.None.} =
  ## Only a genuine successful decode supplies immutable width, signedness and operand roles; raw copies cannot rebind them.
  decoded.completed.memoryOperands
func width*(operands: MemoryOperands): byte {.inline.} =
  ## Report the decoded byte width; zero denotes a non-memory/default fact, never permission to access bytes.
  operands.widthValue
func isLoad*(operands: MemoryOperands): bool {.inline.} =
  ## Loads write their decoded A only after complete memory preflight succeeds.
  operands.loadingValue
func isSigned*(operands: MemoryOperands): bool {.inline.} =
  ## Only byte/halfword/word loads request explicit high-bit extension.
  operands.signedValue
func base*(operands: MemoryOperands): MemoryBase {.inline.} =
  ## Select the original address register without reclassifying an opcode during execution.
  operands.baseValue
func usesImmediate*(operands: MemoryOperands): bool {.inline.} =
  ## Immediate stores read Y; register stores read original A.
  operands.immediateValue

func decodeMemoryOperands(opcode: byte): MemoryOperands =
  ## Derive fixed operand roles only during successful owner decoding; execution/cache hits reuse the result.
  result = default(MemoryOperands)
  case opcode
  of 52..58, 124..130:
    # Load pairs alternate unsigned/signed at 8/16/32 bits, followed by unsigned 64-bit.
    let index = (if opcode <= 58: int(opcode)-52 else: int(opcode)-124)
    result.widthValue = byte(1 shl (index div 2))
    result.loadingValue = true
    result.signedValue = index in [1, 3, 5]
    if opcode >= 124: result.baseValue = MemoryBase.B # Indirect loads consume original B.
  of 30..33:
    # Absolute immediate stores use X and Y without reading an address register.
    result.widthValue = byte(1 shl (int(opcode)-30))
    result.immediateValue = true
  of 59..62:
    # Absolute register stores write the low decoded-width bytes of original A.
    result.widthValue = byte(1 shl (int(opcode)-59))
  of 70..73:
    # Indirect immediate stores use original A plus X and data Y.
    result.widthValue = byte(1 shl (int(opcode)-70))
    result.baseValue = MemoryBase.A
    result.immediateValue = true
  of 120..123:
    # Indirect register stores use original B plus X and data A.
    result.widthValue = byte(1 shl (int(opcode)-120))
    result.baseValue = MemoryBase.B
  else:
    # Successful non-memory decodes retain the explicit zero-width/default facts.
    discard

func boundedRegister(value: byte): range[0'u8..12'u8] {.inline.} =
  ## GP operands saturate at12; separate returns preserve the explicit narrowing proof.
  if value > 12: return 12'u8
  value

func validOpcode*(opcode: byte): bool =
  ## Exact set U from the 0.8.0 instruction tables, including unlikely (2).
  opcode in {0'u8..2'u8, 10'u8, 20'u8, 30'u8..33'u8, 40'u8, 50'u8..62'u8,
    70'u8..73'u8, 80'u8..90'u8, 100'u8..110'u8, 120'u8..161'u8,
    170'u8..175'u8, 180'u8, 190'u8..230'u8}

func terminatesBlock*(opcode: byte): bool =
  ## Exact set T; a host call suspends execution but does not terminate a basic block.
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

proc decode(input: openArray[byte], entry: CodeAddress,
    byteLimit: ProgramByteLimit, jumpLimit: JumpCountLimit, profile: DecodeProfile): ProgramResult[Program] =
  ## Decode canonical framing, check every extent/value before allocation, then capture one owned copy.
  ## entry must name a marked valid opcode; jump targets are checked only when executed, not here.
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
  if jumps > jamJumpEntries:
    return ProgramResult[Program](status: ProgramError.InvalidProgram)
  var cursor = int(count.consumed)
  # The width is an independent one-byte field, including widths zero and above eight.
  if cursor == input.len: return ProgramResult[Program](status: ProgramError.Truncated)
  let width = int(input[cursor])
  inc cursor
  # The current deblob equation limits every jump-table element width to four bytes.
  if width > 4:
    return ProgramResult[Program](status: ProgramError.InvalidProgram)
  let codeCount = natural.decode(input.toOpenArray(cursor, input.len - 1))
  # Canonical naturals give a unique framing; overlong lengths are not alternate formats.
  if not codeCount.ok:
    return ProgramResult[Program](status: (if codeCount.error == natural.truncated:
      ProgramError.Truncated else: ProgramError.NonCanonical))
  cursor += int(codeCount.consumed)
  let codeSize = uint64(codeCount.value)
  if codeSize > jamCodeBytes:
    return ProgramResult[Program](status: ProgramError.InvalidProgram)
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
    if step == codeLength - pc:
      let opcode = input[codeOffset + pc]
      if not terminatesBlock(opcode):
        return ProgramResult[Program](status: ProgramError.InvalidProgram)
      # GP-PVM-004: JAM modules require a final terminator with no fallthrough successor.
      if profile == DecodeProfile.Jam and opcode notin {0'u8, 40'u8, 50'u8, 80'u8, 180'u8}:
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
    jumpOffset: jumpOffset, jumpWidth: width,
    jumps: (if profile == DecodeProfile.Jam and width == 0: 0'u64 else: jumps), profile: profile)))

proc decodeProgram*(input: openArray[byte], entry: CodeAddress,
    byteLimit: ProgramByteLimit, jumpLimit: JumpCountLimit): ProgramResult[Program] =
  ## Decode the pinned paper's raw structure and preserve logical zero-width table entries.
  ## Input is borrowed only during capture; all successful program storage is privately owned.
  decode(input, entry, byteLimit, jumpLimit, DecodeProfile.Paper)

proc decodeJamProgram*(input: openArray[byte], entry: CodeAddress,
    byteLimit: ProgramByteLimit, jumpLimit: JumpCountLimit): ProgramResult[Program] =
  ## Decode for JAM execution with scoped GP-PVM-004/005/006/007/009 PolkaVM compatibility rules.
  ## Reject missing final successors/widths above four; width-zero tables are semantically empty.
  ## Code is at most32 MiB and declared jumps at most16 Mi entries before width-zero normalization.
  ## Original bytes remain owned verbatim; caller limits apply before semantic normalization.
  decode(input, entry, byteLimit, jumpLimit, DecodeProfile.Jam)

proc codeLength*(program: Program): ProgramResult[uint64] =
  ## Return logical code size without publishing backing storage; default handles are typed failures.
  # A default handle has no validated storage to inspect.
  if program.data == nil: return ProgramResult[uint64](status: ProgramError.InvalidOwner)
  ProgramResult[uint64](status: ProgramError.None, completed: uint64(program.data.codeLength))

proc jumpTarget*(program: Program, index: JumpIndex): ProgramResult[CodeAddress] =
  ## Read a table entry by ordinal, including implicit zero values in a zero-width table.
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

func startsBlock(data: ProgramData, pc: int): bool {.requires: pc >= 0 and pc < data.codeLength.} =
  ## The caller proved a marked in-range PC; its closest marked predecessor alone decides membership, with at most25 byte checks.
  if pc == 0: return true # The validated first instruction always begins a block.
  var previous = pc-1
  while previous >= max(0, pc-25):
    # Only the immediately preceding marked instruction can establish this boundary; operand bytes do not count.
    if marked(data.bytes, data.maskOffset, previous):
      return terminatesBlock(data.bytes[data.codeOffset+previous])
    dec previous
  false

func validStaticTarget(data: ProgramData, target: uint64): bool =
  ## Reject absent/unmarked targets before narrowing; owner capture bounds every marker/code access below.
  if target >= uint64(data.codeLength): return false
  let pc = int(target)
  if not marked(data.bytes, data.maskOffset, pc): return false
  startsBlock(data, pc)

proc instruction*(program: Program, address: CodeAddress): ProgramResult[Instruction] =
  ## Copy a decoded instruction; invalid addresses and default handles never yield operands.
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
  # v_blob traversed every marked opcode with this same capped skip. Within the owner extent,
  # the next sequential position is therefore already a validated marked opcode, not an arbitrary byte.
  # pc<codeLength proves both subtractions below; no speculative successor addition can wrap.
  var item = Instruction(address: address, opcode: opcode, skip: skip,
    shape: OperandShape.NoArguments, a: RegisterIndex(0), b: RegisterIndex(0),
    d: RegisterIndex(0), x: Immediate(0), y: Immediate(0), displacement: 0,
    fallthroughPresent: uint64(skip) < uint64(data.codeLength)-pc-1, targetStartsBlock: false,
        registerSlots: default(RegisterSlots), memoryOperands: default(MemoryOperands))
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
    item.registerSlots.aSlot = boundedRegister(byte(first mod 16))
    item.a = RegisterIndex(byte(item.registerSlots.aSlot))
    item.registerSlots.writeSlot = item.registerSlots.aSlot # Extended load writes its decoded A.
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
    item.registerSlots.aSlot = boundedRegister(byte(first mod 16))
    item.a = RegisterIndex(byte(item.registerSlots.aSlot))
    if opcode == 51: item.registerSlots.writeSlot = item.registerSlots.aSlot # Only load_imm is register arithmetic in this family.
    item.x = Immediate(extended(data, pc + 2, min(4, max(0, int(skip) - 1))))
  of 70..73, 80..90:
    # These groups share X and register decoding; Y is immediate or signed offset.
    item.registerSlots.aSlot = boundedRegister(byte(first mod 16))
    item.a = RegisterIndex(byte(item.registerSlots.aSlot))
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
    item.registerSlots.dSlot = boundedRegister(byte(first mod 16))
    item.d = RegisterIndex(byte(item.registerSlots.dSlot))
    item.registerSlots.writeSlot = item.registerSlots.dSlot # Unary/three-register arithmetic writes its explicit D.
    item.registerSlots.aSlot = boundedRegister(byte(first div 16))
    item.a = RegisterIndex(byte(item.registerSlots.aSlot))
  of 120..161, 170..175:
    # Both groups decode low A and high B; the last operand determines their shape.
    item.registerSlots.aSlot = boundedRegister(byte(first mod 16))
    item.a = RegisterIndex(byte(item.registerSlots.aSlot))
    item.registerSlots.bSlot = boundedRegister(byte(first div 16))
    item.b = RegisterIndex(byte(item.registerSlots.bSlot))
    let width = min(4, max(0, int(skip) - 1))
    if opcode <= 161:
      # Arithmetic and indirect memory instructions use a sign-extended immediate.
      item.shape = OperandShape.TwoRegistersImmediate
      if opcode >= 131: item.registerSlots.writeSlot = item.registerSlots.aSlot # Immediate arithmetic writes A; indirect memory retains zero.
      item.x = Immediate(extended(data, pc + 2, width))
    else:
      # Register comparisons use a signed static branch displacement.
      item.shape = OperandShape.TwoRegistersOffset
      item.displacement = offsetOperand(data, pc + 2, width)
  of 180:
    # Dynamic load-and-jump has a second descriptor byte before its two immediates.
    item.shape = OperandShape.TwoRegistersTwoImmediates
    item.registerSlots.aSlot = boundedRegister(byte(first mod 16))
    item.a = RegisterIndex(byte(item.registerSlots.aSlot))
    item.registerSlots.bSlot = boundedRegister(byte(first div 16))
    item.b = RegisterIndex(byte(item.registerSlots.bSlot))
    let xlen = min(4, int(codeByte(data, pc + 2)) mod 8)
    item.x = Immediate(extended(data, pc + 3, xlen))
    item.y = Immediate(extended(data, pc + 3 + uint64(xlen), min(4, max(0, int(skip) - xlen - 2))))
  of 190..230:
    # PR554: every current-paper owner masks the third-register destination to its low nibble.
    item.shape = OperandShape.ThreeRegisters
    item.registerSlots.aSlot = boundedRegister(byte(first mod 16))
    item.a = RegisterIndex(byte(item.registerSlots.aSlot))
    item.registerSlots.bSlot = boundedRegister(byte(first div 16))
    item.b = RegisterIndex(byte(item.registerSlots.bSlot))
    let encoded = int(codeByte(data, pc + 2))
    let destination = encoded mod 16
    item.registerSlots.dSlot = boundedRegister(byte(destination))
    item.d = RegisterIndex(byte(item.registerSlots.dSlot))
    item.registerSlots.writeSlot = item.registerSlots.dSlot # Unary/three-register arithmetic writes its explicit D.
  else:
    # A valid owner cannot contain another marked opcode; retain an explicit failure alternative.
    return ProgramResult[Instruction](status: ProgramError.InvalidInstruction)
  item.memoryOperands = decodeMemoryOperands(opcode) # Derive once after operand validation; cached results carry these facts unchanged.
  if opcode == 1:
    # A present successor after a terminating fallthrough is necessarily a block boundary in the validated chain.
    item.targetStartsBlock = item.fallthroughPresent
  elif opcode in {40'u8, 80'u8..90'u8, 170'u8..175'u8}:
    # Decoded offsets fit signed32; negating their magnitude is safe, while mathematical negative PCs remain invalid.
    if item.displacement < 0:
      let magnitude = uint64(-item.displacement)
      if magnitude <= pc: item.targetStartsBlock = validStaticTarget(data, pc-magnitude)
    else:
      # Captured PCs fit host int and nonnegative offsets fit signed32, so this uint64 sum cannot wrap.
      item.targetStartsBlock = validStaticTarget(data, pc+uint64(item.displacement))
  ProgramResult[Instruction](status: ProgramError.None, completed: item)

proc instructionOpcode*(program: Program, address: CodeAddress): ProgramResult[byte] =
  ## Copy the opcode at a validated marked instruction location without decoding its operands.
  ## Default owners, out-of-range addresses and unmarked bytes retain instruction() errors.
  ## Unlike instructionByte(), this lookup has no zero suffix and never accepts operand locations.
  if program.data == nil:
    # A default handle has no captured code or instruction-marker bitmap.
    return ProgramResult[byte](status: ProgramError.InvalidOwner)
  let data = program.data
  let pc = uint64(address)
  if pc >= uint64(data.codeLength):
    # Establish the host-int bound before narrowing the logical address or inspecting a marker.
    return ProgramResult[byte](status: ProgramError.InvalidInstruction)
  if not marked(data.bytes, data.maskOffset, int(pc)):
    # Literal operand bytes remain non-executable even when they happen to encode valid opcodes.
    return ProgramResult[byte](status: ProgramError.InvalidInstruction)
  # Owner capture already validated every marked opcode; immutable storage preserves that proof.
  ProgramResult[byte](status: ProgramError.None, completed: data.bytes[data.codeOffset + int(pc)])

proc basicBlockStart*(program: Program, address: CodeAddress): ProgramResult[bool] =
  ## Membership in varpi uses a bounded backward search, since skip is at most 24.
  # Establish ownership locally as well as through the instruction result.
  # A default handle has no validated storage to inspect.
  if program.data == nil: return ProgramResult[bool](status: ProgramError.InvalidOwner)
  let decoded = instructionOpcode(program, address)
  # Preserve address failures instead of treating invalid positions as ordinary block members.
  if decoded.error != ProgramError.None: return ProgramResult[bool](status: decoded.error)
  let data = program.data
  ProgramResult[bool](status: ProgramError.None, completed: startsBlock(data, int(uint64(address))))

proc instructionByte*(program: Program, address: CodeAddress): ProgramResult[byte] =
  ## Inspect the raw instruction byte sequence with its normative infinite zero suffix.
  ## Unlike instruction(), this deliberately accepts unmarked operands and out-of-range addresses.
  # A default owner has no byte sequence, even though valid programs have a zero suffix.
  if program.data == nil: return ProgramResult[byte](status: ProgramError.InvalidOwner)
  let data = program.data
  ProgramResult[byte](status: ProgramError.None, completed: codeByte(data, uint64(address)))

proc containingBlockStart*(program: Program, address: CodeAddress): ProgramResult[CodeAddress] =
  ## Find GP startofbasicblock for a valid instruction, including entry in the middle of a block.
  ## The backward byte scan is bounded by the validated program size and retains no storage.
  let current = instructionOpcode(program, address)
  # Reject default owners and invalid addresses before narrowing or scanning bytes.
  if current.error != ProgramError.None:
    return ProgramResult[CodeAddress](status: current.error)
  if program.data == nil:
    # Reestablish the non-nil owner for the pinned compiler's local analysis.
    return ProgramResult[CodeAddress](status: ProgramError.InvalidOwner)
  let data = program.data
  var previous = int(uint64(address)) - 1
  # Only marked terminators create boundaries; operand bytes with the same value do not.
  while previous >= 0:
    if marked(data.bytes, data.maskOffset, previous) and
        terminatesBlock(data.bytes[data.codeOffset + previous]):
      # The next marked instruction is the start of the current block, even for interior entry.
      return ProgramResult[CodeAddress](status: ProgramError.None, completed:
        CodeAddress(uint64(previous + 1 + int(distance(data.bytes, data.maskOffset,
        data.codeLength, previous)))))
    dec previous
  ProgramResult[CodeAddress](status: ProgramError.None, completed: CodeAddress(0))
