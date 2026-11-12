// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Independent raw decoder witnesses from the pinned public InstructionSet implementation.
use polkavm_common::program::{ISA_JamV1, InstructionSet};

pub fn generate(path: &str) {
    // Exercise every raw opcode/length with bit patterns covering signed fields and raw registers.
    let count: u32 = 256 * 25 * 32;
    let mut output = b"PVFDEC01".to_vec();
    output.extend_from_slice(&count.to_le_bytes());
    let mut seed = 0x3141592653589793_u64;
    for raw in 0..256_u32 {
        for length in 1..=25_u32 {
            for sample in 0..32_u8 {
                let mut bytes = [0_u8; 16];
                for byte in &mut bytes {
                    seed ^= seed << 13;
                    seed ^= seed >> 7;
                    seed ^= seed << 17;
                    *byte = seed as u8;
                }
                bytes[0] = raw as u8;
                // Explicit zero and all-one windows complement deterministic random chunks.
                if sample < 2 {
                    bytes[1..].fill(if sample == 0 { 0 } else { 255 });
                }
                let offset = seed as u32;
                let decoded = ISA_JamV1.parse_instruction(
                    raw as usize,
                    u128::from_le_bytes(bytes),
                    offset,
                    length,
                );
                let (opcode, fields) = crate::decode_match::fields(decoded);
                output.extend_from_slice(&bytes);
                output.extend_from_slice(&offset.to_le_bytes());
                output.push(length as u8);
                output.extend_from_slice(&opcode.to_le_bytes());
                for field in fields {
                    output.extend_from_slice(&field.to_le_bytes());
                }
            }
        }
    }
    std::fs::write(path, output).unwrap();
    println!("faithful upstream raw decoder witnesses: {count}");
}
