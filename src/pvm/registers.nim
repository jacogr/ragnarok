# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 register-only instruction mutations; see spec/pvm-registers.md. This evaluator does
## not advance PC, charge gas or publish a machine execution step.
##
## Exposes registerOnlyOpcode, evaluateRegisterWrite, evaluateRegisters and guarded scalar/array results
## for the implemented arithmetic/logic instruction subset.

import ./[program, machine]

type
  RegisterError* {.pure.} = enum ## Unsupported instructions are scope failures, not guest traps; no partial registers escape.
    Uninitialized, None, InvalidInstruction, UnsupportedInstruction
  RegisterResult* = object ## The fixed register array is copied on success and inaccessible for every failure alternative.
    case status: RegisterError
    of None:
      # No references or mutable storage are shared with the input register file.
      completed: RegisterFile
    else:
      # Failed/default alternatives carry only their reason.
      discard

  RegisterWriteResult* = object ## Successful arithmetic evaluation identifies one copied destination/value; failures grant neither.
    case status: RegisterError
    of None:
      # Only the evaluator can create a validated write from an owned decoded instruction.
      completedIndex: RegisterIndex
      completedValue: RegisterValue
    else:
      # Default/invalid/unsupported alternatives contain no writable register selection.
      discard

func error*(r: RegisterWriteResult): RegisterError =
  ## Inspect scalar evaluation status without authorizing either success field.
  r.status
func destination*(r: RegisterWriteResult): RegisterIndex {.inline, requires: r.status ==
    RegisterError.None.} =
  ## Select success before obtaining the evaluator's bounded destination index.
  r.completedIndex
func writeValue*(r: RegisterWriteResult): RegisterValue {.inline, requires: r.status ==
    RegisterError.None.} =
  ## Return a copied register-width bit pattern only for a successful evaluation.
  r.completedValue

func error*(r: RegisterResult): RegisterError =
  ## Inspect the reason without permitting result retagging.
  r.status
func value*(r: RegisterResult): RegisterFile {.inline, requires: r.status == RegisterError.None.} =
  ## Select success before extracting the copied register file.
  r.completed

func registerOnlyOpcode*(opcode: byte): bool =
  ## Identify the complete register-only execution scope before gas charging or register evaluation.
  opcode in {20'u8, 51'u8, 100'u8..110'u8, 131'u8..161'u8, 190'u8..230'u8}

# Sign-extend a low-width bit pattern without host signed overflow or implementation-defined shifts.
func sext(value: uint64, bits: int): uint64 =
  let mask = high(uint64) shr (64 - bits)
  result = value and mask
  # Set only bits above the sign bit when the low-width value is negative.
  if (result and (1'u64 shl (bits - 1))) != 0: result = result or not mask

# Biasing the sign bit turns two's-complement signed ordering into unsigned ordering.
func lessSigned(a, b: uint64): bool =
  (a xor 0x8000000000000000'u64) < (b xor 0x8000000000000000'u64)

# Arithmetic right shift uses explicit sign fill; the zero count never shifts by 64.
func arithmeticRight(value, count: uint64): uint64 =
  let shift = int(count and 63)
  result = value shr shift
  # Only a nonzero shift of a negative bit pattern needs high one bits.
  if shift != 0 and (value shr 63) != 0: result = result or (high(uint64) shl (64 - shift))

# Rotate a masked word right, with a modulo count on both legs to avoid full-width shifts.
func rotateRight(value, count: uint64, bits: int): uint64 =
  let mask = high(uint64) shr (64 - bits)
  let shift = int(count and uint64(bits - 1))
  let word = value and mask
  (word shr shift) or ((word shl ((bits - shift) mod bits)) and mask)

# Two's-complement magnitudes include MIN_INT as a representable unsigned value.
func magnitude(value: uint64): uint64 =
  # Positive patterns need no conversion; negatives use modular negation.
  if (value shr 63) == 0: value
  else: 0'u64 - value

# Signed divide/remainder use unsigned magnitudes so MIN_INT / -1 never reaches host signed division.
func signedDivision(a, b: uint64, remainder: bool): uint64 =
  # The GP explicitly defines division by zero and signed modulo by zero.
  if b == 0:
    return (if remainder: a else: high(uint64))
  let left = magnitude(a)
  let right = magnitude(b)
  var answer = (if remainder: left mod right else: left div right)
  let negative = (if remainder: (a shr 63) != 0 else: ((a xor b) shr 63) != 0)
  # Modular negation also preserves the required MIN_INT overflow result.
  if negative: answer = 0'u64 - answer
  answer

# Compute the upper 64 bits of a 128-bit product using four bounded 32-bit limbs.
func multiplyHigh(a, b: uint64): uint64 =
  let mask = 0xffffffff'u64
  let low = (a and mask) * (b and mask)
  let middle = (a shr 32) * (b and mask) + (low shr 32)
  let carry = middle shr 32
  let combined = (middle and mask) + (a and mask) * (b shr 32)
  (a shr 32) * (b shr 32) + carry + (combined shr 32)

# Count set bits or leading/trailing zeroes in exactly the requested low-width word.
func countBits(value: uint64, bits: int, mode: int): uint64 =
  result = 0
  # Bit-by-bit traversal is bounded by 64 and avoids undefined zero-input intrinsics.
  for index in 0..<bits:
    let position = (if mode == 1: bits - 1 - index else: index)
    let one = (value shr position) and 1
    if mode == 0:
      # Population count includes every bit in the selected width.
      result += one
    elif one == 0:
      # Zero-count modes stop at the first one from their respective end.
      inc result
    else:
      # A one completes the contiguous zero prefix/suffix.
      break

proc evaluateRegisterWrite*(decoded: ProgramResult[Instruction],
    registers: RegisterFile): RegisterWriteResult {.inline.} =
  ## Evaluate a private validated instruction result without repeating its owner/PC lookup.
  ## Failed/default results and non-register instructions fail before reading any payload or array.
  ## All operands use the original copied register file, including source/destination aliases.
  # Invalid owners and unmarked/out-of-range addresses never yield executable operands.
  if decoded.error != ProgramError.None:
    return RegisterWriteResult(status: RegisterError.InvalidInstruction)
  let item = decoded.value
  # The implemented set excludes control flow, host calls and all memory instructions.
  if not registerOnlyOpcode(item.opcode):
    return RegisterWriteResult(status: RegisterError.UnsupportedInstruction)
  let a = uint64(registers[int(byte(item.a))])
  let b = uint64(registers[int(byte(item.b))])
  let x = uint64(item.x)
  var destination = int(byte(item.d))
  # Immediate forms write A; the other forms write D, as specified by each operand table.
  if item.opcode == 20 or item.opcode == 51 or item.opcode in 131'u8..161'u8:
    destination = int(byte(item.a))
  var answer = uint64(registers[destination])
  # Each alternative applies the named GP mutation using unsigned bit patterns.
  case item.opcode
  of 20:
    # load_imm_64 reads only the pre-mutation operands.
    answer = x
  of 51:
    # load_imm reads only the pre-mutation operands.
    answer = x
  of 100:
    # move_reg reads only the pre-mutation operands.
    answer = a
  of 101:
    # count_set_bits_64 reads only the pre-mutation operands.
    answer = countBits(a, 64, 0)
  of 102:
    # count_set_bits_32 reads only the pre-mutation operands.
    answer = countBits(a, 32, 0)
  of 103:
    # leading_zero_bits_64 reads only the pre-mutation operands.
    answer = countBits(a, 64, 1)
  of 104:
    # leading_zero_bits_32 reads only the pre-mutation operands.
    answer = countBits(a, 32, 1)
  of 105:
    # trailing_zero_bits_64 reads only the pre-mutation operands.
    answer = countBits(a, 64, 2)
  of 106:
    # trailing_zero_bits_32 reads only the pre-mutation operands.
    answer = countBits(a, 32, 2)
  of 107:
    # sign_extend_8 reads only the pre-mutation operands.
    answer = sext(a, 8)
  of 108:
    # sign_extend_16 reads only the pre-mutation operands.
    answer = sext(a, 16)
  of 109:
    # zero_extend_16 reads only the pre-mutation operands.
    answer = a and 65535
  of 110:
    # reverse_bytes reads only the pre-mutation operands.
    answer = 0
    # Move each original octet to its opposite position.
    for i in 0..<8: answer = answer or (((a shr (8 * i)) and 255) shl (8 * (7 - i)))
  of 131:
    # add_imm_32 reads only the pre-mutation operands.
    answer = sext(b + x, 32)
  of 132:
    # and_imm reads only the pre-mutation operands.
    answer = b and x
  of 133:
    # xor_imm reads only the pre-mutation operands.
    answer = b xor x
  of 134:
    # or_imm reads only the pre-mutation operands.
    answer = b or x
  of 135:
    # mul_imm_32 reads only the pre-mutation operands.
    answer = sext(b * x, 32)
  of 136:
    # set_lt_u_imm reads only the pre-mutation operands.
    answer = uint64(b < x)
  of 137:
    # set_lt_s_imm reads only the pre-mutation operands.
    answer = uint64(lessSigned(b, x))
  of 138:
    # shlo_l_imm_32 reads only the pre-mutation operands.
    answer = sext(b shl int(x and 31), 32)
  of 139:
    # shlo_r_imm_32 reads only the pre-mutation operands.
    answer = sext((b and 0xffffffff'u64) shr int(x and 31), 32)
  of 140:
    # shar_r_imm_32 reads only the pre-mutation operands.
    answer = arithmeticRight(sext(b, 32), x and 31)
  of 141:
    # neg_add_imm_32 reads only the pre-mutation operands.
    answer = sext(x - b, 32)
  of 142:
    # set_gt_u_imm reads only the pre-mutation operands.
    answer = uint64(b > x)
  of 143:
    # set_gt_s_imm reads only the pre-mutation operands.
    answer = uint64(lessSigned(x, b))
  of 144:
    # shlo_l_imm_alt_32 reads only the pre-mutation operands.
    answer = sext(x shl int(b and 31), 32)
  of 145:
    # shlo_r_imm_alt_32 reads only the pre-mutation operands.
    answer = sext((x and 0xffffffff'u64) shr int(b and 31), 32)
  of 146:
    # shar_r_imm_alt_32 reads only the pre-mutation operands.
    answer = arithmeticRight(sext(x, 32), b and 31)
  of 147:
    # cmov_iz_imm reads only the pre-mutation operands.
    answer = (if b == 0: x else: a)
  of 148:
    # cmov_nz_imm reads only the pre-mutation operands.
    answer = (if b != 0: x else: a)
  of 149:
    # add_imm_64 reads only the pre-mutation operands.
    answer = b + x
  of 150:
    # mul_imm_64 reads only the pre-mutation operands.
    answer = b * x
  of 151:
    # shlo_l_imm_64 reads only the pre-mutation operands.
    answer = b shl int(x and 63)
  of 152:
    # shlo_r_imm_64 reads only the pre-mutation operands.
    answer = b shr int(x and 63)
  of 153:
    # shar_r_imm_64 reads only the pre-mutation operands.
    answer = arithmeticRight(b, x)
  of 154:
    # neg_add_imm_64 reads only the pre-mutation operands.
    answer = x - b
  of 155:
    # shlo_l_imm_alt_64 reads only the pre-mutation operands.
    answer = x shl int(b and 63)
  of 156:
    # shlo_r_imm_alt_64 reads only the pre-mutation operands.
    answer = x shr int(b and 63)
  of 157:
    # shar_r_imm_alt_64 reads only the pre-mutation operands.
    answer = arithmeticRight(x, b)
  of 158:
    # rot_r_64_imm reads only the pre-mutation operands.
    answer = rotateRight(b, x, 64)
  of 159:
    # rot_r_64_imm_alt reads only the pre-mutation operands.
    answer = rotateRight(x, b, 64)
  of 160:
    # rot_r_32_imm reads only the pre-mutation operands.
    answer = sext(rotateRight(b, x, 32), 32)
  of 161:
    # rot_r_32_imm_alt reads only the pre-mutation operands.
    answer = sext(rotateRight(x, b, 32), 32)
  of 190:
    # add_32 reads only the pre-mutation operands.
    answer = sext(a + b, 32)
  of 191:
    # sub_32 reads only the pre-mutation operands.
    answer = sext(a - b, 32)
  of 192:
    # mul_32 reads only the pre-mutation operands.
    answer = sext(a * b, 32)
  of 193:
    # div_u_32 reads only the pre-mutation operands.
    answer = (if (b and 0xffffffff'u64) == 0: high(uint64) else: sext((a and 0xffffffff'u64) div (
        b and 0xffffffff'u64), 32))
  of 194:
    # div_s_32 reads only the pre-mutation operands.
    answer = sext(signedDivision(sext(a, 32), sext(b, 32), false), 32)
  of 195:
    # rem_u_32 reads only the pre-mutation operands.
    answer = sext((if (b and 0xffffffff'u64) == 0: a else: (a and 0xffffffff'u64) mod (b and
        0xffffffff'u64)), 32)
  of 196:
    # rem_s_32 reads only the pre-mutation operands.
    answer = sext(signedDivision(sext(a, 32), sext(b, 32), true), 32)
  of 197:
    # shlo_l_32 reads only the pre-mutation operands.
    answer = sext(a shl int(b and 31), 32)
  of 198:
    # shlo_r_32 reads only the pre-mutation operands.
    answer = sext((a and 0xffffffff'u64) shr int(b and 31), 32)
  of 199:
    # shar_r_32 reads only the pre-mutation operands.
    answer = arithmeticRight(sext(a, 32), b and 31)
  of 200:
    # add_64 reads only the pre-mutation operands.
    answer = a + b
  of 201:
    # sub_64 reads only the pre-mutation operands.
    answer = a - b
  of 202:
    # mul_64 reads only the pre-mutation operands.
    answer = a * b
  of 203:
    # div_u_64 reads only the pre-mutation operands.
    answer = (if b == 0: high(uint64) else: a div b)
  of 204:
    # div_s_64 reads only the pre-mutation operands.
    answer = signedDivision(a, b, false)
  of 205:
    # rem_u_64 reads only the pre-mutation operands.
    answer = (if b == 0: a else: a mod b)
  of 206:
    # rem_s_64 reads only the pre-mutation operands.
    answer = signedDivision(a, b, true)
  of 207:
    # shlo_l_64 reads only the pre-mutation operands.
    answer = a shl int(b and 63)
  of 208:
    # shlo_r_64 reads only the pre-mutation operands.
    answer = a shr int(b and 63)
  of 209:
    # shar_r_64 reads only the pre-mutation operands.
    answer = arithmeticRight(a, b)
  of 210:
    # and reads only the pre-mutation operands.
    answer = a and b
  of 211:
    # xor reads only the pre-mutation operands.
    answer = a xor b
  of 212:
    # or reads only the pre-mutation operands.
    answer = a or b
  of 213:
    # mul_upper_s_s reads only the pre-mutation operands.
    answer = multiplyHigh(a, b) - (if (a shr 63) != 0: b else: 0'u64) - (if (b shr 63) !=
        0: a else: 0'u64)
  of 214:
    # mul_upper_u_u reads only the pre-mutation operands.
    answer = multiplyHigh(a, b)
  of 215:
    # mul_upper_s_u reads only the pre-mutation operands.
    answer = multiplyHigh(a, b) - (if (a shr 63) != 0: b else: 0'u64)
  of 216:
    # set_lt_u reads only the pre-mutation operands.
    answer = uint64(a < b)
  of 217:
    # set_lt_s reads only the pre-mutation operands.
    answer = uint64(lessSigned(a, b))
  of 218:
    # cmov_iz reads only the pre-mutation operands.
    answer = (if b == 0: a else: answer)
  of 219:
    # cmov_nz reads only the pre-mutation operands.
    answer = (if b != 0: a else: answer)
  of 220:
    # rot_l_64 reads only the pre-mutation operands.
    answer = rotateRight(a, 0'u64 - b, 64)
  of 221:
    # rot_l_32 reads only the pre-mutation operands.
    answer = sext(rotateRight(a, 0'u64 - b, 32), 32)
  of 222:
    # rot_r_64 reads only the pre-mutation operands.
    answer = rotateRight(a, b, 64)
  of 223:
    # rot_r_32 reads only the pre-mutation operands.
    answer = sext(rotateRight(a, b, 32), 32)
  of 224:
    # and_inv reads only the pre-mutation operands.
    answer = a and not b
  of 225:
    # or_inv reads only the pre-mutation operands.
    answer = a or not b
  of 226:
    # xnor reads only the pre-mutation operands.
    answer = not (a xor b)
  of 227:
    # max reads only the pre-mutation operands.
    answer = (if lessSigned(a, b): b else: a)
  of 228:
    # max_u reads only the pre-mutation operands.
    answer = max(a, b)
  of 229:
    # min reads only the pre-mutation operands.
    answer = (if lessSigned(a, b): a else: b)
  of 230:
    # min_u reads only the pre-mutation operands.
    answer = min(a, b)
  else:
    # Keep scope rejection explicit even though the supported set was checked above.
    return RegisterWriteResult(status: RegisterError.UnsupportedInstruction)
  RegisterWriteResult(status: RegisterError.None, completedIndex: RegisterIndex(byte(destination)),
    completedValue: RegisterValue(answer))

proc evaluateRegisters*(decoded: ProgramResult[Instruction],
    registers: RegisterFile): RegisterResult =
  ## Compatibility evaluation materializes the complete copied array only after the scalar write succeeds.
  let written = evaluateRegisterWrite(decoded, registers)
  if written.error != RegisterError.None:
    return RegisterResult(status: written.error) # Failed scalar results carry no destination or value.
  var copied = registers
  copied[int(byte(written.destination))] = written.writeValue
  RegisterResult(status: RegisterError.None, completed: copied)

proc evaluateRegisters*(program: Program, pc: CodeAddress,
    registers: RegisterFile): RegisterResult =
  ## Look up one owned instruction and evaluate its register mutation without advancing PC or gas.
  ## This compatibility entry point retains the same validation, scope and copied-register contract.
  evaluateRegisters(instruction(program, pc), registers)
