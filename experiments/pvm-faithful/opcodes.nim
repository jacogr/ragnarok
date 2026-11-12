# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Generated JamV1 table derived from PolkaVM program.rs; see LICENSES/NOTICE.md.
## Regenerate with generate_tables.py; numeric gaps are invalid instructions.
## Source SHA256: 47301945d67921156dbb5fd8b4b00e960d3db9a87ebc0bd821d9225bd31ff2e1

import std/assertions

type
  Opcode* {.pure.} = enum
    ## The source JamV1 opcode numbers, with an explicit invalid sentinel.
    op_trap = 0
    op_fallthrough = 1
    op_unlikely = 2
    op_ecalli = 10
    op_load_imm64 = 20
    op_store_imm_u8 = 30
    op_store_imm_u16 = 31
    op_store_imm_u32 = 32
    op_store_imm_u64 = 33
    op_jump = 40
    op_jump_indirect = 50
    op_load_imm = 51
    op_load_u8 = 52
    op_load_i8 = 53
    op_load_u16 = 54
    op_load_i16 = 55
    op_load_u32 = 56
    op_load_i32 = 57
    op_load_u64 = 58
    op_store_u8 = 59
    op_store_u16 = 60
    op_store_u32 = 61
    op_store_u64 = 62
    op_store_imm_indirect_u8 = 70
    op_store_imm_indirect_u16 = 71
    op_store_imm_indirect_u32 = 72
    op_store_imm_indirect_u64 = 73
    op_load_imm_and_jump = 80
    op_branch_eq_imm = 81
    op_branch_not_eq_imm = 82
    op_branch_less_unsigned_imm = 83
    op_branch_less_or_equal_unsigned_imm = 84
    op_branch_greater_or_equal_unsigned_imm = 85
    op_branch_greater_unsigned_imm = 86
    op_branch_less_signed_imm = 87
    op_branch_less_or_equal_signed_imm = 88
    op_branch_greater_or_equal_signed_imm = 89
    op_branch_greater_signed_imm = 90
    op_move_reg = 100
    op_count_set_bits_64 = 101
    op_count_set_bits_32 = 102
    op_count_leading_zero_bits_64 = 103
    op_count_leading_zero_bits_32 = 104
    op_count_trailing_zero_bits_64 = 105
    op_count_trailing_zero_bits_32 = 106
    op_sign_extend_8 = 107
    op_sign_extend_16 = 108
    op_zero_extend_16 = 109
    op_reverse_byte = 110
    op_store_indirect_u8 = 120
    op_store_indirect_u16 = 121
    op_store_indirect_u32 = 122
    op_store_indirect_u64 = 123
    op_load_indirect_u8 = 124
    op_load_indirect_i8 = 125
    op_load_indirect_u16 = 126
    op_load_indirect_i16 = 127
    op_load_indirect_u32 = 128
    op_load_indirect_i32 = 129
    op_load_indirect_u64 = 130
    op_add_imm_32 = 131
    op_and_imm = 132
    op_xor_imm = 133
    op_or_imm = 134
    op_mul_imm_32 = 135
    op_set_less_than_unsigned_imm = 136
    op_set_less_than_signed_imm = 137
    op_shift_logical_left_imm_32 = 138
    op_shift_logical_right_imm_32 = 139
    op_shift_arithmetic_right_imm_32 = 140
    op_negate_and_add_imm_32 = 141
    op_set_greater_than_unsigned_imm = 142
    op_set_greater_than_signed_imm = 143
    op_shift_logical_left_imm_alt_32 = 144
    op_shift_logical_right_imm_alt_32 = 145
    op_shift_arithmetic_right_imm_alt_32 = 146
    op_cmov_if_zero_imm = 147
    op_cmov_if_not_zero_imm = 148
    op_add_imm_64 = 149
    op_mul_imm_64 = 150
    op_shift_logical_left_imm_64 = 151
    op_shift_logical_right_imm_64 = 152
    op_shift_arithmetic_right_imm_64 = 153
    op_negate_and_add_imm_64 = 154
    op_shift_logical_left_imm_alt_64 = 155
    op_shift_logical_right_imm_alt_64 = 156
    op_shift_arithmetic_right_imm_alt_64 = 157
    op_rotate_right_imm_64 = 158
    op_rotate_right_imm_alt_64 = 159
    op_rotate_right_imm_32 = 160
    op_rotate_right_imm_alt_32 = 161
    op_branch_eq = 170
    op_branch_not_eq = 171
    op_branch_less_unsigned = 172
    op_branch_less_signed = 173
    op_branch_greater_or_equal_unsigned = 174
    op_branch_greater_or_equal_signed = 175
    op_load_imm_and_jump_indirect = 180
    op_add_32 = 190
    op_sub_32 = 191
    op_mul_32 = 192
    op_div_unsigned_32 = 193
    op_div_signed_32 = 194
    op_rem_unsigned_32 = 195
    op_rem_signed_32 = 196
    op_shift_logical_left_32 = 197
    op_shift_logical_right_32 = 198
    op_shift_arithmetic_right_32 = 199
    op_add_64 = 200
    op_sub_64 = 201
    op_mul_64 = 202
    op_div_unsigned_64 = 203
    op_div_signed_64 = 204
    op_rem_unsigned_64 = 205
    op_rem_signed_64 = 206
    op_shift_logical_left_64 = 207
    op_shift_logical_right_64 = 208
    op_shift_arithmetic_right_64 = 209
    op_and = 210
    op_xor = 211
    op_or = 212
    op_mul_upper_signed_signed = 213
    op_mul_upper_unsigned_unsigned = 214
    op_mul_upper_signed_unsigned = 215
    op_set_less_than_unsigned = 216
    op_set_less_than_signed = 217
    op_cmov_if_zero = 218
    op_cmov_if_not_zero = 219
    op_rotate_left_64 = 220
    op_rotate_left_32 = 221
    op_rotate_right_64 = 222
    op_rotate_right_32 = 223
    op_and_inverted = 224
    op_or_inverted = 225
    op_xnor = 226
    op_maximum = 227
    op_maximum_unsigned = 228
    op_minimum = 229
    op_minimum_unsigned = 230
    op_invalid = 256
  OperandFormat* {.pure.} = enum
    ## Source macro operand group; these choose the pinned read_args routines.
    fmtInvalid, fmtNone, fmtRegImm, fmtRegImmOffset, fmtRegImm2, fmtRegs2Imm, fmtRegs2Offset,
      fmtRegs3, fmtOffset, fmtImm, fmtImm2, fmtRegs2, fmtRegs2Imm2, fmtRegImm64

proc operandFormat*(raw: byte): OperandFormat =
  ## Reject gaps instead of assuming contiguous enum membership.
  case raw
  of 0, 1, 2:
    result = OperandFormat.fmtNone
  of 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62:
    result = OperandFormat.fmtRegImm
  of 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90:
    result = OperandFormat.fmtRegImmOffset
  of 70, 71, 72, 73:
    result = OperandFormat.fmtRegImm2
  of 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138,
      139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157,
      158, 159, 160, 161:
    result = OperandFormat.fmtRegs2Imm
  of 170, 171, 172, 173, 174, 175:
    result = OperandFormat.fmtRegs2Offset
  of 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208,
      209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227,
      228, 229, 230:
    result = OperandFormat.fmtRegs3
  of 40:
    result = OperandFormat.fmtOffset
  of 10:
    result = OperandFormat.fmtImm
  of 30, 31, 32, 33:
    result = OperandFormat.fmtImm2
  of 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110:
    result = OperandFormat.fmtRegs2
  of 180:
    result = OperandFormat.fmtRegs2Imm2
  of 20:
    result = OperandFormat.fmtRegImm64
  else: result = OperandFormat.fmtInvalid

const opcodeTable = [
  Opcode.op_trap, Opcode.op_fallthrough, Opcode.op_unlikely, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_ecalli, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_load_imm64,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_store_imm_u8, Opcode.op_store_imm_u16,
  Opcode.op_store_imm_u32, Opcode.op_store_imm_u64, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_jump, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_jump_indirect, Opcode.op_load_imm,
  Opcode.op_load_u8, Opcode.op_load_i8, Opcode.op_load_u16, Opcode.op_load_i16,
  Opcode.op_load_u32, Opcode.op_load_i32, Opcode.op_load_u64, Opcode.op_store_u8,
  Opcode.op_store_u16, Opcode.op_store_u32, Opcode.op_store_u64, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_store_imm_indirect_u8, Opcode.op_store_imm_indirect_u16,
  Opcode.op_store_imm_indirect_u32, Opcode.op_store_imm_indirect_u64, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_load_imm_and_jump, Opcode.op_branch_eq_imm, Opcode.op_branch_not_eq_imm,
  Opcode.op_branch_less_unsigned_imm, Opcode.op_branch_less_or_equal_unsigned_imm,
  Opcode.op_branch_greater_or_equal_unsigned_imm, Opcode.op_branch_greater_unsigned_imm,
  Opcode.op_branch_less_signed_imm,
  Opcode.op_branch_less_or_equal_signed_imm, Opcode.op_branch_greater_or_equal_signed_imm,
  Opcode.op_branch_greater_signed_imm, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_move_reg,
  Opcode.op_count_set_bits_64, Opcode.op_count_set_bits_32, Opcode.op_count_leading_zero_bits_64,
  Opcode.op_count_leading_zero_bits_32, Opcode.op_count_trailing_zero_bits_64,
  Opcode.op_count_trailing_zero_bits_32, Opcode.op_sign_extend_8, Opcode.op_sign_extend_16,
  Opcode.op_zero_extend_16, Opcode.op_reverse_byte, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_store_indirect_u8, Opcode.op_store_indirect_u16, Opcode.op_store_indirect_u32,
  Opcode.op_store_indirect_u64, Opcode.op_load_indirect_u8, Opcode.op_load_indirect_i8,
  Opcode.op_load_indirect_u16, Opcode.op_load_indirect_i16,
  Opcode.op_load_indirect_u32, Opcode.op_load_indirect_i32, Opcode.op_load_indirect_u64,
  Opcode.op_add_imm_32, Opcode.op_and_imm, Opcode.op_xor_imm, Opcode.op_or_imm,
  Opcode.op_mul_imm_32,
  Opcode.op_set_less_than_unsigned_imm, Opcode.op_set_less_than_signed_imm,
  Opcode.op_shift_logical_left_imm_32, Opcode.op_shift_logical_right_imm_32,
  Opcode.op_shift_arithmetic_right_imm_32, Opcode.op_negate_and_add_imm_32,
  Opcode.op_set_greater_than_unsigned_imm, Opcode.op_set_greater_than_signed_imm,
  Opcode.op_shift_logical_left_imm_alt_32, Opcode.op_shift_logical_right_imm_alt_32,
  Opcode.op_shift_arithmetic_right_imm_alt_32, Opcode.op_cmov_if_zero_imm,
  Opcode.op_cmov_if_not_zero_imm, Opcode.op_add_imm_64, Opcode.op_mul_imm_64,
  Opcode.op_shift_logical_left_imm_64,
  Opcode.op_shift_logical_right_imm_64, Opcode.op_shift_arithmetic_right_imm_64,
  Opcode.op_negate_and_add_imm_64, Opcode.op_shift_logical_left_imm_alt_64,
  Opcode.op_shift_logical_right_imm_alt_64, Opcode.op_shift_arithmetic_right_imm_alt_64,
  Opcode.op_rotate_right_imm_64, Opcode.op_rotate_right_imm_alt_64,
  Opcode.op_rotate_right_imm_32, Opcode.op_rotate_right_imm_alt_32, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_branch_eq, Opcode.op_branch_not_eq,
  Opcode.op_branch_less_unsigned, Opcode.op_branch_less_signed,
  Opcode.op_branch_greater_or_equal_unsigned, Opcode.op_branch_greater_or_equal_signed,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_load_imm_and_jump_indirect, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_add_32, Opcode.op_sub_32,
  Opcode.op_mul_32, Opcode.op_div_unsigned_32, Opcode.op_div_signed_32, Opcode.op_rem_unsigned_32,
  Opcode.op_rem_signed_32, Opcode.op_shift_logical_left_32, Opcode.op_shift_logical_right_32,
  Opcode.op_shift_arithmetic_right_32,
  Opcode.op_add_64, Opcode.op_sub_64, Opcode.op_mul_64, Opcode.op_div_unsigned_64,
  Opcode.op_div_signed_64, Opcode.op_rem_unsigned_64, Opcode.op_rem_signed_64,
  Opcode.op_shift_logical_left_64,
  Opcode.op_shift_logical_right_64, Opcode.op_shift_arithmetic_right_64, Opcode.op_and,
  Opcode.op_xor, Opcode.op_or, Opcode.op_mul_upper_signed_signed,
  Opcode.op_mul_upper_unsigned_unsigned, Opcode.op_mul_upper_signed_unsigned,
  Opcode.op_set_less_than_unsigned, Opcode.op_set_less_than_signed, Opcode.op_cmov_if_zero,
  Opcode.op_cmov_if_not_zero, Opcode.op_rotate_left_64, Opcode.op_rotate_left_32,
  Opcode.op_rotate_right_64, Opcode.op_rotate_right_32,
  Opcode.op_and_inverted, Opcode.op_or_inverted, Opcode.op_xnor, Opcode.op_maximum,
  Opcode.op_maximum_unsigned, Opcode.op_minimum, Opcode.op_minimum_unsigned, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid,
  Opcode.op_invalid, Opcode.op_invalid, Opcode.op_invalid
]

proc opcode*(raw: byte): Opcode =
  ## Lookup validates gaps without an unchecked enum cast.
  opcodeTable[int(raw)]
