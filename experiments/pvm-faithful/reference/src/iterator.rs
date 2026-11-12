// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Independent bounded/unbounded iterator and jump-admission witnesses for arbitrary JamV1 code.
use polkavm_common::program::{
    ISA_JamV1, InstructionSetKind, Instructions, ProgramBlob, ProgramCounter, ProgramParts,
};

pub fn generate(path: &str) {
    // Keep lengths below 128 so the public from_parts input uses one canonical length byte.
    let lengths = [0, 1, 8, 24, 25, 31, 32, 33, 64, 127];
    let mut output = b"PVFITR02".to_vec();
    output.extend_from_slice(&(lengths.len() as u32 * 32).to_le_bytes());
    let mut random = 0x9e3779b97f4a7c15_u64;
    for length in lengths {
        for sample in 0..32 {
            let mut code = vec![0_u8; length];
            let mut mask = vec![0_u8; length.div_ceil(8)];
            for byte in code.iter_mut().chain(mask.iter_mut()) {
                random ^= random << 13;
                random ^= random >> 7;
                random ^= random << 17;
                *byte = random as u8;
            }
            // Long zero gaps, full boundaries and actual fallthrough endings complement noise.
            if sample < 4 {
                mask.fill(if sample == 0 { 255 } else { 0 });
                if length != 0 {
                    mask[0] |= 1;
                    code[0] = if sample == 2 { 1 } else { 0 };
                    if sample == 3 {
                        mask[(length - 1) / 8] |= 1 << ((length - 1) % 8);
                    }
                }
            }
            if length % 8 != 0 {
                *mask.last_mut().unwrap() &= (1 << (length % 8)) - 1;
            }
            let mut encoded = vec![0, 0, length as u8];
            encoded.extend_from_slice(&code);
            encoded.extend_from_slice(&mask);
            let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
            parts.code_and_jump_table = encoded.into();
            let blob = ProgramBlob::from_parts(parts).unwrap();
            output.extend_from_slice(&(length as u32).to_le_bytes());
            output.extend_from_slice(&code);
            output.extend_from_slice(&mask);
            for at in 0..length + 2 {
                output.push(u8::from(
                    blob.scan_is_jump_target_valid(ISA_JamV1, ProgramCounter(at as u32)),
                ));
                let start = polkavm_common::program::scan_find_start_of_basic_block(
                    ISA_JamV1, &code, &mask, at as u32,
                );
                output.extend_from_slice(&start.unwrap_or(u32::MAX).to_le_bytes());
            }
            for bounded in [false, true] {
                for offset in [
                    0,
                    1,
                    24,
                    length.saturating_sub(1) as u32,
                    length as u32,
                    length as u32 + 1,
                    u32::MAX,
                ] {
                    let iterator = if bounded {
                        Instructions::new_bounded(ISA_JamV1, &code, &mask, offset)
                    } else {
                        Instructions::new_unbounded(ISA_JamV1, &code, &mask, offset)
                    };
                    let rows: Vec<_> = iterator.collect();
                    assert!(rows.len() <= length + 2);
                    output.extend_from_slice(&offset.to_le_bytes());
                    output.push(u8::from(bounded));
                    output.extend_from_slice(&(rows.len() as u32).to_le_bytes());
                    for row in rows {
                        output.extend_from_slice(&row.offset.0.to_le_bytes());
                        output.extend_from_slice(&row.next_offset.0.to_le_bytes());
                        let (opcode, fields) = crate::decode_match::fields(row.kind);
                        output.extend_from_slice(&opcode.to_le_bytes());
                        for field in fields {
                            output.extend_from_slice(&field.to_le_bytes());
                        }
                    }
                }
            }
        }
    }
    std::fs::write(path, output).unwrap();
    println!(
        "faithful upstream iterator witnesses: {}",
        lengths.len() * 32
    );
}
