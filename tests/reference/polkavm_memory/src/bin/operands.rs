// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Check independent frozen operand expectations through the public JamV1 parsed-instruction API.
// @@PvmReference={"suite":"pvm_operand_reference","input":"pvm-operand.bin","engine":false}
use polkavm::{ProgramBlob, ProgramCounter};
use polkavm_common::program::{Instruction, InstructionSetKind, ProgramParts, RawReg, Reg};

/// Decode a complete fixed little-endian field only after checking its enclosing extent.
fn number(data: &[u8], at: usize, width: usize) -> u64 {
    let bytes = data.get(at..at.checked_add(width).unwrap()).unwrap();
    assert!((1..=8).contains(&width));
    bytes
        .iter()
        .enumerate()
        .fold(0, |value, (i, byte)| value | ((*byte as u64) << (8 * i)))
}

/// Map frozen paper operands to public instruction variants; this contains no operand decoding.
fn expected(op: u8, a: RawReg, b: RawReg, d: RawReg, x: u64, y: u64, target: u32) -> Instruction {
    match op {
        // Variant names and argument order are the pinned public API; values remain independent.
        0 => Instruction::trap,
        1 => Instruction::fallthrough,
        2 => Instruction::unlikely,
        10 => Instruction::ecalli(x as i32),
        20 => Instruction::load_imm64(a, x),
        30 => Instruction::store_imm_u8(x as i32, y as i32),
        31 => Instruction::store_imm_u16(x as i32, y as i32),
        32 => Instruction::store_imm_u32(x as i32, y as i32),
        33 => Instruction::store_imm_u64(x as i32, y as i32),
        40 => Instruction::jump(target),
        50 => Instruction::jump_indirect(a, x as i32),
        51 => Instruction::load_imm(a, x as i32),
        52 => Instruction::load_u8(a, x as i32),
        53 => Instruction::load_i8(a, x as i32),
        54 => Instruction::load_u16(a, x as i32),
        55 => Instruction::load_i16(a, x as i32),
        56 => Instruction::load_u32(a, x as i32),
        57 => Instruction::load_i32(a, x as i32),
        58 => Instruction::load_u64(a, x as i32),
        59 => Instruction::store_u8(a, x as i32),
        60 => Instruction::store_u16(a, x as i32),
        61 => Instruction::store_u32(a, x as i32),
        62 => Instruction::store_u64(a, x as i32),
        70 => Instruction::store_imm_indirect_u8(a, x as i32, y as i32),
        71 => Instruction::store_imm_indirect_u16(a, x as i32, y as i32),
        72 => Instruction::store_imm_indirect_u32(a, x as i32, y as i32),
        73 => Instruction::store_imm_indirect_u64(a, x as i32, y as i32),
        80 => Instruction::load_imm_and_jump(a, x as i32, target),
        81 => Instruction::branch_eq_imm(a, x as i32, target),
        82 => Instruction::branch_not_eq_imm(a, x as i32, target),
        83 => Instruction::branch_less_unsigned_imm(a, x as i32, target),
        84 => Instruction::branch_less_or_equal_unsigned_imm(a, x as i32, target),
        85 => Instruction::branch_greater_or_equal_unsigned_imm(a, x as i32, target),
        86 => Instruction::branch_greater_unsigned_imm(a, x as i32, target),
        87 => Instruction::branch_less_signed_imm(a, x as i32, target),
        88 => Instruction::branch_less_or_equal_signed_imm(a, x as i32, target),
        89 => Instruction::branch_greater_or_equal_signed_imm(a, x as i32, target),
        90 => Instruction::branch_greater_signed_imm(a, x as i32, target),
        100 => Instruction::move_reg(d, a),
        101 => Instruction::count_set_bits_64(d, a),
        102 => Instruction::count_set_bits_32(d, a),
        103 => Instruction::count_leading_zero_bits_64(d, a),
        104 => Instruction::count_leading_zero_bits_32(d, a),
        105 => Instruction::count_trailing_zero_bits_64(d, a),
        106 => Instruction::count_trailing_zero_bits_32(d, a),
        107 => Instruction::sign_extend_8(d, a),
        108 => Instruction::sign_extend_16(d, a),
        109 => Instruction::zero_extend_16(d, a),
        110 => Instruction::reverse_byte(d, a),
        120 => Instruction::store_indirect_u8(a, b, x as i32),
        121 => Instruction::store_indirect_u16(a, b, x as i32),
        122 => Instruction::store_indirect_u32(a, b, x as i32),
        123 => Instruction::store_indirect_u64(a, b, x as i32),
        124 => Instruction::load_indirect_u8(a, b, x as i32),
        125 => Instruction::load_indirect_i8(a, b, x as i32),
        126 => Instruction::load_indirect_u16(a, b, x as i32),
        127 => Instruction::load_indirect_i16(a, b, x as i32),
        128 => Instruction::load_indirect_u32(a, b, x as i32),
        129 => Instruction::load_indirect_i32(a, b, x as i32),
        130 => Instruction::load_indirect_u64(a, b, x as i32),
        131 => Instruction::add_imm_32(a, b, x as i32),
        132 => Instruction::and_imm(a, b, x as i32),
        133 => Instruction::xor_imm(a, b, x as i32),
        134 => Instruction::or_imm(a, b, x as i32),
        135 => Instruction::mul_imm_32(a, b, x as i32),
        136 => Instruction::set_less_than_unsigned_imm(a, b, x as i32),
        137 => Instruction::set_less_than_signed_imm(a, b, x as i32),
        138 => Instruction::shift_logical_left_imm_32(a, b, x as i32),
        139 => Instruction::shift_logical_right_imm_32(a, b, x as i32),
        140 => Instruction::shift_arithmetic_right_imm_32(a, b, x as i32),
        141 => Instruction::negate_and_add_imm_32(a, b, x as i32),
        142 => Instruction::set_greater_than_unsigned_imm(a, b, x as i32),
        143 => Instruction::set_greater_than_signed_imm(a, b, x as i32),
        144 => Instruction::shift_logical_left_imm_alt_32(a, b, x as i32),
        145 => Instruction::shift_logical_right_imm_alt_32(a, b, x as i32),
        146 => Instruction::shift_arithmetic_right_imm_alt_32(a, b, x as i32),
        147 => Instruction::cmov_if_zero_imm(a, b, x as i32),
        148 => Instruction::cmov_if_not_zero_imm(a, b, x as i32),
        149 => Instruction::add_imm_64(a, b, x as i32),
        150 => Instruction::mul_imm_64(a, b, x as i32),
        151 => Instruction::shift_logical_left_imm_64(a, b, x as i32),
        152 => Instruction::shift_logical_right_imm_64(a, b, x as i32),
        153 => Instruction::shift_arithmetic_right_imm_64(a, b, x as i32),
        154 => Instruction::negate_and_add_imm_64(a, b, x as i32),
        155 => Instruction::shift_logical_left_imm_alt_64(a, b, x as i32),
        156 => Instruction::shift_logical_right_imm_alt_64(a, b, x as i32),
        157 => Instruction::shift_arithmetic_right_imm_alt_64(a, b, x as i32),
        158 => Instruction::rotate_right_imm_64(a, b, x as i32),
        159 => Instruction::rotate_right_imm_alt_64(a, b, x as i32),
        160 => Instruction::rotate_right_imm_32(a, b, x as i32),
        161 => Instruction::rotate_right_imm_alt_32(a, b, x as i32),
        170 => Instruction::branch_eq(a, b, target),
        171 => Instruction::branch_not_eq(a, b, target),
        172 => Instruction::branch_less_unsigned(a, b, target),
        173 => Instruction::branch_less_signed(a, b, target),
        174 => Instruction::branch_greater_or_equal_unsigned(a, b, target),
        175 => Instruction::branch_greater_or_equal_signed(a, b, target),
        180 => Instruction::load_imm_and_jump_indirect(a, b, x as i32, y as i32),
        190 => Instruction::add_32(d, a, b),
        191 => Instruction::sub_32(d, a, b),
        192 => Instruction::mul_32(d, a, b),
        193 => Instruction::div_unsigned_32(d, a, b),
        194 => Instruction::div_signed_32(d, a, b),
        195 => Instruction::rem_unsigned_32(d, a, b),
        196 => Instruction::rem_signed_32(d, a, b),
        197 => Instruction::shift_logical_left_32(d, a, b),
        198 => Instruction::shift_logical_right_32(d, a, b),
        199 => Instruction::shift_arithmetic_right_32(d, a, b),
        200 => Instruction::add_64(d, a, b),
        201 => Instruction::sub_64(d, a, b),
        202 => Instruction::mul_64(d, a, b),
        203 => Instruction::div_unsigned_64(d, a, b),
        204 => Instruction::div_signed_64(d, a, b),
        205 => Instruction::rem_unsigned_64(d, a, b),
        206 => Instruction::rem_signed_64(d, a, b),
        207 => Instruction::shift_logical_left_64(d, a, b),
        208 => Instruction::shift_logical_right_64(d, a, b),
        209 => Instruction::shift_arithmetic_right_64(d, a, b),
        210 => Instruction::and(d, a, b),
        211 => Instruction::xor(d, a, b),
        212 => Instruction::or(d, a, b),
        213 => Instruction::mul_upper_signed_signed(d, a, b),
        214 => Instruction::mul_upper_unsigned_unsigned(d, a, b),
        215 => Instruction::mul_upper_signed_unsigned(d, a, b),
        216 => Instruction::set_less_than_unsigned(d, a, b),
        217 => Instruction::set_less_than_signed(d, a, b),
        218 => Instruction::cmov_if_zero(d, a, b),
        219 => Instruction::cmov_if_not_zero(d, a, b),
        220 => Instruction::rotate_left_64(d, a, b),
        221 => Instruction::rotate_left_32(d, a, b),
        222 => Instruction::rotate_right_64(d, a, b),
        223 => Instruction::rotate_right_32(d, a, b),
        224 => Instruction::and_inverted(d, a, b),
        225 => Instruction::or_inverted(d, a, b),
        226 => Instruction::xnor(d, a, b),
        227 => Instruction::maximum(d, a, b),
        228 => Instruction::maximum_unsigned(d, a, b),
        229 => Instruction::minimum(d, a, b),
        230 => Instruction::minimum_unsigned(d, a, b),
        _ => panic!("unknown paper opcode"),
    }
}

/// Replay every original blob without rewriting operands, bitmasks, targets or code lengths.
fn main() {
    let data = std::fs::read(std::env::args().nth(1).unwrap()).unwrap();
    assert_eq!(&data[..8], b"PVMOPR01");
    assert_eq!(number(&data, 8, 4), 62550);
    let mut cursor = 12;
    for row in 0..62550 {
        // Prove header/body bounds before reading fields, converting sizes or parsing the original wire.
        assert!(data.len().saturating_sub(cursor) >= 40);
        let size = number(&data, cursor, 4) as usize;
        let pc = number(&data, cursor + 4, 4) as u32;
        assert!(size <= 128 && matches!(pc, 0 | 3));
        let end = cursor.checked_add(40 + size).unwrap();
        assert!(end <= data.len());
        let op = data[cursor + 8];
        let skip = data[cursor + 9];
        assert!(skip <= 24 && data[cursor + 10] <= 12 && data[cursor + 15] <= 8);
        let reg = |at| RawReg::from(Reg::from_raw(data[at] as u32).unwrap());
        let a = reg(cursor + 11);
        let b = reg(cursor + 12);
        let d = reg(cursor + 14);
        let x = number(&data, cursor + 16, 8);
        let y = number(&data, cursor + 24, 8);
        // The GP signed displacement is deliberately adapted to this API's wrapped absolute target.
        let target = pc.wrapping_add(number(&data, cursor + 32, 8) as u32);
        let wanted = expected(op, a, b, d, x, y, target);
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = data[cursor + 40..end].to_vec().into();
        let blob = ProgramBlob::from_parts(parts).unwrap();
        let actual = blob
            .instructions_bounded_at(ProgramCounter(pc))
            .next()
            .unwrap();
        assert_eq!(actual.offset.0, pc, "row {row}");
        assert_eq!(actual.next_offset.0, pc + 1 + skip as u32, "row {row}");
        assert_eq!(actual.kind, wanted, "row {row}, op {op}, skip {skip}");
        cursor = end;
    }
    assert_eq!(cursor, data.len());
    println!("62550 operand-shape witnesses through public JamV1 parser");
}
