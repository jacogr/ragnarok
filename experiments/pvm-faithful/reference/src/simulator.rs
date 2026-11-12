// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Independent Full(L2Hit), B64 scheduling witnesses from pinned PolkaVM's public simulator.
use polkavm_common::program::{
    ISA_JamV1, InstructionSet, InstructionSetKind, ParsedInstruction, ProgramCounter,
};
use polkavm_common::simulator::{CacheModel, Simulator};
use polkavm_common::utils::{GasVisitorT, B64};

fn random(seed: &mut u64) -> u64 {
    // Fixed bitwise PRNG makes witness generation stable across native architectures.
    *seed ^= *seed << 13;
    *seed ^= *seed >> 7;
    *seed ^= *seed << 17;
    *seed
}

pub fn generate(path: &str) {
    let count = 1152_u32;
    let mut output = b"PVFGAS01".to_vec();
    output.extend_from_slice(&count.to_le_bytes());
    let mut seed = 0x3c6ef372fe94f82b_u64;
    for case in 0..count {
        let mut code = vec![51_u8; 256];
        for position in [0, 63, 127, 255] {
            code[position] = if case % 2 == 0 { 0 } else { 2 };
        }
        output.extend_from_slice(&(code.len() as u32).to_le_bytes());
        output.extend_from_slice(&code);
        let steps = 161_u32;
        output.extend_from_slice(&steps.to_le_bytes());
        let mut simulator =
            Simulator::<B64, _>::new(&code, InstructionSetKind::JamV1, CacheModel::L2Hit, ());
        assert!(simulator.is_at_start_of_basic_block());
        assert!(simulator.take_block_cost().is_none());
        for step in 0..steps {
            let mut bytes = [0_u8; 16];
            for byte in &mut bytes {
                *byte = random(&mut seed) as u8;
            }
            // Each raw opcode gets three homogeneous dependency patterns; the last quarter mixes all.
            if case < 768 {
                bytes[0] = (case % 256) as u8;
            }
            if case < 256 {
                bytes[1..].fill(0);
            } else if case < 512 {
                bytes[1..].fill(255);
            }
            if case >= 1024 {
                // Long mixed nonterminal blocks cross ROB wraparound and competing resource classes.
                let operations = [
                    51, 20, 100, 131, 149, 190, 200, 192, 202, 193, 203, 197, 207, 147, 218, 59,
                    120, 52, 124, 210, 224, 10, 2,
                ];
                bytes[0] = operations[(seed as usize) % operations.len()];
            }
            if step == steps - 1 {
                bytes[0] = 0;
            }
            let offset = if step % 8 == 0 {
                seed as u32
            } else {
                seed as u32 % 256
            };
            let length = 1 + (seed as u32 % 25);
            let kind = ISA_JamV1.parse_instruction(
                bytes[0] as usize,
                u128::from_le_bytes(bytes),
                offset,
                length,
            );
            ParsedInstruction {
                kind,
                offset: ProgramCounter(offset),
                next_offset: ProgramCounter(offset.wrapping_add(length)),
            }
            .visit_parsing(&mut simulator);
            let cost = simulator.take_block_cost();
            output.extend_from_slice(&bytes);
            output.extend_from_slice(&offset.to_le_bytes());
            output.push(length as u8);
            output.push(u8::from(cost.is_some()));
            output.extend_from_slice(&cost.unwrap_or(0).to_le_bytes());
            output.push(u8::from(simulator.is_at_start_of_basic_block()));
        }
        assert!(simulator.is_at_start_of_basic_block());
    }
    std::fs::write(path, output).unwrap();
    println!(
        "faithful upstream simulator witnesses: {count} sequences, {} instructions",
        count * 161
    );
}
