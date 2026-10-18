# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise PVM program framing, opcode/operand decoding, jump tables, ownership and
## malformed-input boundaries.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, syncio]
import ../../../src/pvm/program
import ../../../src/codec/natural

# Encode one natural for independent framing construction; decoder logic is never reused.
proc appendNatural(bytes: var seq[byte], value: uint64) =
  let encoded = encode(JamNatural(value))
  # Only the encoder's occupied prefix belongs to the fixture.
  for i in 0..<encoded.len: bytes.add(encoded.bytes[i])

# Build a test program from literal code and explicit marked offsets, with no automatic validation.
proc blob(code: openArray[byte], starts: openArray[int], width = 0,
    jumps = 0'u64, table: openArray[byte] = []): seq[byte] =
  result = @[]
  appendNatural(result, jumps)
  result.add(byte(width))
  appendNatural(result, uint64(code.len))
  # The caller supplies table bytes verbatim, including deliberately malformed values.
  for b in table: result.add(b)
  # Literal instruction bytes are independent from the production operand decoder.
  for b in code: result.add(b)
  var mask = newSeq[byte](code.len div 8 + int(code.len mod 8 != 0))
  # Mark only explicitly selected code offsets, leaving all padding bits clear.
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for b in mask: result.add(b)

# Apply modest test resource ceilings unless a test explicitly exercises larger logical counts.
proc read(bytes: openArray[byte], entry = 0'u64): ProgramResult[Program] =
  decodeProgram(bytes, CodeAddress(entry), ProgramByteLimit(4096), JumpCountLimit(1000))

# Select success before extracting an instruction, making missing test fixtures fail immediately.
proc ins(code: openArray[byte], starts: openArray[int], pc = 0'u64): Instruction =
  let decoded = read(blob(code, starts), pc)
  assert decoded.error == ProgramError.None
  let item = instruction(decoded.value, CodeAddress(pc))
  assert item.error == ProgramError.None
  item.value

# Default handles/results cannot fabricate a valid empty program or payload.
let defaultResult = default(ProgramResult[Program])
assert defaultResult.error == ProgramError.Uninitialized
assert codeLength(default(Program)).error == ProgramError.InvalidOwner
assert instruction(default(Program), CodeAddress(0)).error == ProgramError.InvalidOwner
assert jumpTarget(default(Program), JumpIndex(0)).error == ProgramError.InvalidOwner
assert basicBlockStart(default(Program), CodeAddress(0)).error == ProgramError.InvalidOwner

let minimal = blob([0'u8], [0])
assert minimal == @[0'u8, 0, 1, 0, 1]
assert read(minimal).error == ProgramError.None
# Every strict prefix of the smallest program is incomplete.
for size in 0..<minimal.len:
  assert read(minimal.toOpenArray(0, size - 1)).error == ProgramError.Truncated
assert read(@[0'u8, 0, 0]).error == ProgramError.InvalidProgram
assert read(@[0'u8, 0, 1, 0, 129]).error == ProgramError.NonCanonical
assert read(@[0'u8, 0, 1, 0, 1, 0]).error == ProgramError.TrailingBytes
assert read(@[128'u8, 0, 0, 1, 0, 1]).error == ProgramError.NonCanonical
assert read(@[0'u8, 0, 128, 1, 0, 1]).error == ProgramError.NonCanonical
assert read(blob([0'u8], [])).error == ProgramError.InvalidProgram
assert read(minimal, high(uint64)).error == ProgramError.InvalidInstruction
assert decodeProgram(minimal, CodeAddress(0), ProgramByteLimit(4), JumpCountLimit(0)).error ==
    ProgramError.LimitExceeded

# Exhaust the opcode space using an independent literal table of published ranges.
for op in 0..255:
  let expected = op in 0..2 or op == 10 or op == 20 or op in 30..33 or op == 40 or
    op in 50..62 or op in 70..73 or op in 80..90 or op in 100..110 or
    op in 120..161 or op in 170..175 or op == 180 or op in 190..230
  let terminal = op in [0, 1, 40, 50, 180] or op in 80..90 or op in 170..175
  assert validOpcode(byte(op)) == expected
  assert terminatesBlock(byte(op)) == terminal
  assert (read(blob([byte(op), 0], [0, 1])).error == ProgramError.None) == expected
  assert (read(blob([byte(op)], [0])).error == ProgramError.None) == terminal

# Skip at 24 is allowed; a 25-byte operand gap reaches an unmarked instruction and must fail.
for gap in 0..26:
  var code = newSeq[byte](gap + 2)
  code[0] = 2
  let parsed = read(blob(code, [0, gap + 1]))
  assert (parsed.error == ProgramError.None) == (gap <= 24)
  if parsed.error == ProgramError.None:
    # Accepted skip distances preserve both instruction and basic-block membership.
    assert instruction(parsed.value, CodeAddress(0)).value.skip == gap
    assert not basicBlockStart(parsed.value, CodeAddress(uint64(gap + 1))).value

# All thirteen operand forms: explicit values catch register naming and immediate-width mistakes.
assert ins([2'u8, 0], [0, 1]).shape == OperandShape.NoArguments
let immediate = ins([10'u8, 128, 0], [0, 2])
assert immediate.shape == OperandShape.OneImmediate and uint64(immediate.x) == high(uint64) - 127
let wide = ins([20'u8, 255, 1, 2, 3, 4, 5, 6, 7, 128, 0], [0, 10])
assert wide.shape == OperandShape.ExtendedImmediate and byte(wide.a) == 12
assert uint64(wide.x) == 0x8007060504030201'u64
let pair = ins([30'u8, 1, 255, 128, 0], [0, 4])
assert pair.shape == OperandShape.TwoImmediates
assert uint64(pair.x) == high(uint64) and uint64(pair.y) == high(uint64) - 127
let jump = ins([40'u8, 255], [0])
assert jump.shape == OperandShape.OneOffset and jump.displacement == -1
let ri = ins([51'u8, 255, 128, 0], [0, 3])
assert ri.shape == OperandShape.RegisterImmediate and byte(ri.a) == 12
assert uint64(ri.x) == high(uint64) - 127
let rii = ins([70'u8, 31, 255, 127, 0], [0, 4])
assert rii.shape == OperandShape.RegisterTwoImmediates and byte(rii.a) == 12
assert uint64(rii.x) == high(uint64) and uint64(rii.y) == 127
let rio = ins([80'u8, 31, 127, 128], [0])
assert rio.shape == OperandShape.RegisterImmediateOffset and uint64(rio.x) == 127
assert rio.displacement == -128
let rr = ins([100'u8, 0x23, 0], [0, 2])
assert rr.shape == OperandShape.TwoRegisters and byte(rr.d) == 3 and byte(rr.a) == 2
let rri = ins([120'u8, 0x23, 255, 0], [0, 3])
assert rri.shape == OperandShape.TwoRegistersImmediate
assert byte(rri.a) == 3 and byte(rri.b) == 2 and uint64(rri.x) == high(uint64)
let rro = ins([170'u8, 0x23, 255], [0])
assert rro.shape == OperandShape.TwoRegistersOffset and rro.displacement == -1
let rrii = ins([180'u8, 0x23, 1, 128, 127], [0])
assert rrii.shape == OperandShape.TwoRegistersTwoImmediates
assert byte(rrii.a) == 3 and byte(rrii.b) == 2
assert uint64(rrii.x) == high(uint64) - 127 and uint64(rrii.y) == 127
let rrr = ins([190'u8, 0x23, 16, 0], [0, 3])
assert rrr.shape == OperandShape.ThreeRegisters
assert byte(rrr.a) == 3 and byte(rrr.b) == 2 and byte(rrr.d) == 12

# Short operands use the global code stream, including later opcodes, then infinite zero padding.
let crossing = ins([20'u8, 0, 40, 255], [0, 1, 2])
assert crossing.skip == 0 and uint64(crossing.x) == 0xff28
assert ins([180'u8], [0]).x.uint64 == 0
assert ins([180'u8], [0]).y.uint64 == 0
assert ins([40'u8], [0]).displacement == 0
assert ins([80'u8, 0x40], [0]).x.uint64 == 0

# Exhaust descriptor bytes and short lengths against direct arithmetic expectations.
for descriptor in 0..255:
  for length in 0..8:
    var code = newSeq[byte](length + 2)
    code[0] = 180
    code[1] = byte(descriptor)
    # A fixed sign-bearing pattern makes both width and sign-extension boundaries observable.
    for i in 2..<code.len: code[i] = 255
    let item = ins(code, [0])
    assert byte(item.a) == byte(min(12, descriptor mod 16))
    assert byte(item.b) == byte(min(12, descriptor div 16))
    # X has four bytes when the descriptor exists; missing high bytes are zero padding.
    let present = min(4, max(0, length - 1))
    let expectedX = (if present == 4: high(uint64) else: (1'u64 shl (present * 8)) - 1)
    assert uint64(item.x) == expectedX
    # Y is selected only after the descriptor and four X bytes; all its selected bytes are ff.
    let expectedY = (if length > 5: high(uint64) else: 0'u64)
    assert uint64(item.y) == expectedY

# Compact signed immediates and offsets cover every supported width and both sign extremes.
for width in 0..4:
  var code = newSeq[byte](width + 2)
  code[0] = 10
  # Set only the most significant operand byte; zero-width operands remain exactly zero.
  if width > 0: code[width] = 128
  let decoded = ins(code, [0, width + 1])
  let magnitude = (if width == 0: 0'u64 else: 1'u64 shl (width * 8 - 1))
  let expected = (if width == 0: 0'u64 else: high(uint64) - magnitude + 1)
  assert uint64(decoded.x) == expected
  code[0] = 40
  assert ins(code, [0, width + 1]).displacement == -int64(magnitude)
  # Positive extremes exercise the same width boundary without sign extension.
  if width > 0:
    code[width] = 127
    assert ins(code, [0, width + 1]).displacement == (127'i64 shl ((width - 1) * 8))

# Rich framing rejects every missing suffix byte, including inside table/code/mask payloads.
let rich = blob([2'u8, 0, 0, 1, 0, 0, 0, 0, 0], [0, 3, 8], 4, 2,
  [0'u8, 0, 0, 0, 255, 255, 255, 255])
assert read(rich).error == ProgramError.None
for size in 0..<rich.len:
  assert read(rich.toOpenArray(0, size - 1)).error != ProgramError.None
let richOwner = read(rich).value
assert basicBlockStart(richOwner, CodeAddress(8)).value
assert not basicBlockStart(richOwner, CodeAddress(3)).value
assert instruction(richOwner, CodeAddress(2)).error == ProgramError.InvalidInstruction
assert read(rich, 8).error == ProgramError.None

# Width zero and widths up to 255 are valid fixed encodings when their values fit registers.
for width in [0, 1, 4, 8, 9, 255]:
  var table = newSeq[byte](width)
  if width != 0:
    # A target outside the code is structurally valid; execution will enforce target membership.
    table[0] = 255
  let decoded = read(blob([0'u8], [0], width, 1, table))
  assert decoded.error == ProgramError.None
  assert uint64(jumpTarget(decoded.value, JumpIndex(0)).value) == (if width ==
      0: 0'u64 else: 255'u64)
  assert jumpTarget(decoded.value, JumpIndex(1)).error == ProgramError.InvalidIndex
  if width > 8:
    # Any nonzero high byte leaves the register domain, even when the full payload is present.
    table[8] = 1
    assert read(blob([0'u8], [0], width, 1, table)).error == ProgramError.InvalidJumpValue
let hugeZero = blob([0'u8], [0], 0, high(uint64))
assert read(hugeZero).error == ProgramError.LimitExceeded
let huge = decodeProgram(hugeZero, CodeAddress(0), ProgramByteLimit(100), JumpCountLimit(high(uint64)))
assert huge.error == ProgramError.None
assert uint64(jumpTarget(huge.value, JumpIndex(high(uint64) - 1)).value) == 0
assert read(blob([0'u8], [0], 255, 1000)).error == ProgramError.Truncated
var hugeCode: seq[byte] = @[0'u8, 0]
appendNatural(hugeCode, high(uint64))
assert read(hugeCode).error == ProgramError.Truncated

# Retained handles survive input mutation, while returned operand copies cannot mutate the owner.
var mutable = blob([1'u8, 2, 0], [0, 1, 2])
let captured = read(mutable)
assert captured.error == ProgramError.None
let retained = captured.value
mutable[3] = 255
assert instruction(retained, CodeAddress(0)).value.opcode == 1
assert basicBlockStart(retained, CodeAddress(0)).value
assert basicBlockStart(retained, CodeAddress(1)).value
assert not basicBlockStart(retained, CodeAddress(2)).value
assert instruction(retained, CodeAddress(3)).error == ProgramError.InvalidInstruction
let operandEntry = blob([40'u8, 0], [0])
assert read(operandEntry, 1).error == ProgramError.InvalidInstruction

# Deterministic malformed-input fuzzing exercises all framing paths without exception allowances.
var seed = 0x7a1f9833'u64
for iteration in 0..<10000:
  var bytes = newSeq[byte](iteration mod 80)
  # Xorshift is a reproducible byte generator, not a production random source.
  for i in 0..<bytes.len:
    seed = seed xor (seed shl 13)
    seed = seed xor (seed shr 7)
    seed = seed xor (seed shl 17)
    bytes[i] = byte(seed and 255)
  let parsed = read(bytes)
  if parsed.error == ProgramError.None:
    # Any accepted blob must expose its validated first instruction and positive code extent.
    assert codeLength(parsed.value).value > 0
    assert instruction(parsed.value, CodeAddress(0)).error == ProgramError.None

echo "PVM program decoding passed"
