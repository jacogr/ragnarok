// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Blob admission witnesses from pristine public ProgramParts and ProgramBlob APIs.
use polkavm_common::program::{asm, InstructionSetKind, ProgramBlob, ProgramParts, Reg};
use polkavm_common::writer::ProgramBlobBuilder;

fn framed(bytes: &mut [u8]) {
    // Mutations with valid outer framing exercise inner checks instead of only length rejection.
    let length = bytes.len() as u64;
    if bytes.len() >= 13 {
        bytes[5..13].copy_from_slice(&length.to_le_bytes());
    }
}

fn bytes(output: &mut Vec<u8>, value: &[u8]) {
    // Length-prefixed complete section payloads prevent hash-only or prefix-only comparisons.
    output.extend_from_slice(&(value.len() as u32).to_le_bytes());
    output.extend_from_slice(value);
}

pub fn generate(path: &str) {
    let mut cases = Vec::new();
    for scale in [0, 1, 128, 4096] {
        let mut builder = ProgramBlobBuilder::new(InstructionSetKind::JamV1);
        builder.set_ro_data_size(scale);
        builder.set_rw_data_size(scale);
        builder.set_stack_size(scale);
        builder.set_ro_data(vec![0x35; scale.min(32) as usize]);
        builder.set_rw_data(vec![0x97; scale.min(32) as usize]);
        builder.add_import(b"host");
        builder.add_export_by_instruction(0, b"entry");
        builder.set_code(
            &[asm::load_imm(Reg::A0, -1), asm::jump(1), asm::trap()],
            &[0, 1],
        );
        builder.add_custom_section(128, vec![1, 2, 3]);
        builder.add_custom_section(129, vec![4, 5]);
        builder.add_custom_section(130, vec![6]);
        builder.add_custom_section(131, vec![7, 8]);
        let original = builder.into_vec().unwrap();
        cases.push(original.clone());
        for length in 0..original.len() {
            let mut truncated = original[..length].to_vec();
            cases.push(truncated.clone());
            framed(&mut truncated);
            cases.push(truncated);
        }
        for at in 0..original.len() {
            for mask in [1, 0x80, 0xff] {
                let mut changed = original.clone();
                changed[at] ^= mask;
                framed(&mut changed);
                cases.push(changed);
            }
        }
        // Source accepts bytes after EOF if the declared outer length includes them.
        let mut trailing = original.clone();
        trailing.extend_from_slice(&[1, 2, 3, 4]);
        framed(&mut trailing);
        cases.push(trailing);
        // Unknown optional sections remain skippable before EOF.
        let mut optional = original;
        optional.pop();
        optional.extend_from_slice(&[255, 3, 11, 22, 33, 0]);
        framed(&mut optional);
        cases.push(optional);
    }
    let mut output = b"PVFBLB01".to_vec();
    output.extend_from_slice(&(cases.len() as u32).to_le_bytes());
    let mut accepted = 0;
    for input in &cases {
        bytes(&mut output, input);
        let parsed = ProgramBlob::parse(input.clone().into());
        if input.get(..4) == Some(b"PVM\0") && input.len() >= 14 && input[4] != 3 {
            // The diagnostic's explicit ISA subset is represented separately from invalid input.
            output.push(2);
            continue;
        }
        let Ok(blob) = parsed else {
            output.push(0);
            continue;
        };
        output.push(1);
        accepted += 1;
        let parts = ProgramParts::from_bytes(input.clone().into()).unwrap();
        for size in [blob.ro_data_size(), blob.rw_data_size(), blob.stack_size()] {
            output.extend_from_slice(&size.to_le_bytes());
        }
        for section in [
            &parts.ro_data,
            &parts.rw_data,
            &parts.code_and_jump_table,
            &parts.import_offsets,
            &parts.import_symbols,
            &parts.exports,
            &parts.debug_strings,
            &parts.debug_line_programs,
            &parts.debug_line_program_ranges,
            &parts.metadata_hash,
        ] {
            bytes(&mut output, section);
        }
        bytes(&mut output, blob.code());
        bytes(&mut output, blob.bitmask());
        output.extend_from_slice(&blob.jump_table().len().to_le_bytes());
        for target in blob.jump_table() {
            output.extend_from_slice(&target.0.to_le_bytes());
        }
    }
    std::fs::write(path, output).unwrap();
    println!(
        "faithful upstream blob witnesses: {}, accepted: {accepted}",
        cases.len()
    );
}
