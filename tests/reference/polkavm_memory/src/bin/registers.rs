// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Cross-check the existing independent Gray Paper arithmetic corpus through public PolkaVM APIs.
// @@PvmReference={"input":"pvm-registers.bin","suite":"pvm_registers"}
use polkavm::{
    BackendKind, Config, Engine, InterruptKind, Module, ModuleConfig, ProgramBlob, ProgramCounter,
    ProgramParts, Reg,
};
use polkavm_common::program::InstructionSetKind;
// Read one field after the full fixed-record corpus extent is validated.
fn word(data: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(data[at..at + 8].try_into().unwrap())
}
fn main() {
    // The caller supplies independently generated expectations; the engine never generates them.
    let path = std::env::args()
        .nth(1)
        .expect("provide a PVMREG01 corpus path");
    let data = std::fs::read(path).unwrap();
    assert!(data.len() >= 12 && &data[..8] == b"PVMREG01");
    let count = u32::from_le_bytes(data[8..12].try_into().unwrap()) as usize;
    assert!(count > 32000);
    assert_eq!(
        count
            .checked_mul(51)
            .and_then(|bytes| bytes.checked_add(12)),
        Some(data.len())
    );
    let mut config = Config::default();
    config.set_backend(Some(BackendKind::Interpreter));
    let engine = Engine::new(&config).unwrap();
    let mut seen = [false; 256];
    // Each module runs the original operand bytes, then traps before any unrelated instruction.
    for row in 0..count {
        let at = 12 + row * 51;
        let op = data[at];
        let descriptor = data[at + 1];
        let encoded_destination = data[at + 2];
        let immediate = word(&data, at + 3);
        let mut code = vec![op, descriptor];
        // Encode widths independently of both the engine parser and the Nim decoder.
        if op == 20 {
            code.extend_from_slice(&immediate.to_le_bytes());
        // Compact four-byte immediates deliberately discard the upper sign-extension bytes.
        } else if op == 51 || (131..=161).contains(&op) {
            code.extend_from_slice(&(immediate as u32).to_le_bytes());
        // Three-register operations carry a separate saturated destination byte.
        } else if (190..=230).contains(&op) {
            code.push(encoded_destination);
        }
        let stop = code.len();
        code.push(0);
        // Only the opcode and trailing trap are marked; all operand bytes remain unmarked.
        let mut mask = vec![0_u8; (code.len() + 7) / 8];
        mask[0] = 1;
        mask[stop / 8] |= 1 << (stop % 8);
        let mut wire = vec![0_u8, 0, code.len() as u8];
        wire.extend(code);
        wire.extend(mask);
        // Public ProgramParts accepts the exact legacy JamV1 code/jump-table framing.
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = wire.into();
        let blob = ProgramBlob::from_parts(parts).unwrap();
        let module = Module::from_blob(&engine, &ModuleConfig::new(), blob).unwrap();
        let mut instance = module.instantiate().unwrap();
        let mut input = std::array::from_fn::<u64, 13, _>(|index| 100 + index as u64);
        // Match the independent fixture's four variable register slots and fixed sentinels.
        for (slot, index) in [0, 1, 2, 12].into_iter().enumerate() {
            input[index] = word(&data, at + 11 + slot * 8);
        }
        // Set every architectural register before beginning actual interpreted execution.
        for (index, value) in input.into_iter().enumerate() {
            instance.set_reg(Reg::from_raw(index as u32).unwrap(), value);
        }
        instance.set_next_program_counter(ProgramCounter(0));
        assert!(matches!(instance.run().unwrap(), InterruptKind::Trap));
        assert_eq!(instance.program_counter().unwrap().0, stop as u32);
        // The paper selects destination from A or the explicit third byte, saturating to r12.
        let destination =
            if (100..=110).contains(&op) || op == 20 || op == 51 || (131..=161).contains(&op) {
                (descriptor % 16).min(12)
            } else {
                encoded_destination.min(12)
            } as usize;
        // Verify every register, so an engine exit or a preserved sentinel cannot masquerade as success.
        for (index, original) in input.into_iter().enumerate() {
            let expected = if index == destination {
                word(&data, at + 43)
            } else {
                original
            };
            let actual = instance.reg(Reg::from_raw(index as u32).unwrap());
            assert_eq!(actual, expected, "row={row} opcode={op} register={index}");
        }
        seen[op as usize] = true;
    }
    assert_eq!(seen.into_iter().filter(|value| *value).count(), 85);
    println!("PolkaVM JamV1 arithmetic cross-check passed: {count} rows, 85 opcodes");
}
