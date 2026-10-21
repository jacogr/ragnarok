// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Executed destination-byte and gas observations retain independent GP/JAM expectations.
// @@PvmReference={"input":"pvm-destination.bin","suite":"pvm_destination_reference"}
use polkavm::{
    CacheModel, CostModelKind, GasMeteringKind, InterruptKind, Module, ModuleConfig, ProgramBlob,
    ProgramCounter, ProgramParts, Reg,
};
use polkavm_common::program::InstructionSetKind;

// Read fixed little-endian fields after their complete record extent has been validated.
fn word(data: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(data[at..at + 8].try_into().unwrap())
}

fn main() {
    let data = std::fs::read(std::env::args().nth(1).expect("provide PVMDST01 corpus")).unwrap();
    assert!(data.len() >= 116 && &data[..8] == b"PVMDST01");
    let count = u32::from_le_bytes(data[8..12].try_into().unwrap()) as usize;
    assert_eq!(count, 41 * 256 * 3);
    assert_eq!(data.len(), 116 + count * 52);
    let engine = ragnarok_memory_probe::engine(false);
    let mut profile = ModuleConfig::new();
    profile.set_gas_metering(Some(GasMeteringKind::Sync));
    profile.set_cost_model(Some(CostModelKind::Full(CacheModel::L2Hit)));
    let mut adapted = 0;
    for row in 0..count {
        // Original bytecode is never rewritten to hide the high destination bits.
        let at = 116 + row * 52;
        let op = data[at];
        let descriptor = data[at + 1];
        let encoded = data[at + 2];
        let variant = data[at + 3] as usize;
        assert!((190..=230).contains(&op) && variant < 3);
        let paper = encoded.min(12);
        let destination = (encoded % 16).min(12);
        if paper != destination {
            adapted += 1;
        }
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = vec![0_u8, 0, 4, op, descriptor, encoded, 0, 9].into();
        let module =
            Module::from_blob(&engine, &profile, ProgramBlob::from_parts(parts).unwrap()).unwrap();
        let price = word(&data, at + 36);
        assert!(price > 0 && price < 1000);
        assert_eq!(
            module.calculate_gas_cost_for(ProgramCounter(0)),
            Some(price as i64),
            "row {row}"
        );
        let mut instance = module.instantiate().unwrap();
        for i in 0..13 {
            instance.set_reg(
                Reg::from_raw(i as u32).unwrap(),
                word(&data, 12 + ((i + 3 * variant) % 13) * 8),
            );
        }
        instance.set_gas((price + 7) as i64);
        instance.set_next_program_counter(ProgramCounter(0));
        assert!(
            matches!(instance.run().unwrap(), InterruptKind::Trap),
            "row {row}"
        );
        assert_eq!(instance.program_counter(), Some(ProgramCounter(3)));
        assert_eq!(instance.gas(), 7);
        for i in 0..13 {
            // All unrelated registers retain their independently frozen shared sentinel table.
            let expected = if i == usize::from(destination) {
                word(&data, at + 12)
            } else {
                word(&data, 12 + ((i + 3 * variant) % 13) * 8)
            };
            assert_eq!(
                instance.reg(Reg::from_raw(i as u32).unwrap()),
                expected,
                "row {row} reg {i}"
            );
        }
    }
    // A caller-like prefix makes the decoded destination observable as Trap versus successful return.
    for encoded in [0x10_u8, 0xff] {
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = vec![
            0_u8, 0, 11, 51, 1, 7, 51, 2, 11, 190, 33, encoded, 50, 0, 73, 2,
        ]
        .into();
        let module =
            Module::from_blob(&engine, &profile, ProgramBlob::from_parts(parts).unwrap()).unwrap();
        let mut instance = module.instantiate().unwrap();
        instance.set_reg(Reg::RA, polkavm::RETURN_TO_HOST.into());
        instance.set_gas(100);
        instance.set_next_program_counter(ProgramCounter(0));
        let exit = instance.run().unwrap();
        if encoded == 0x10 {
            assert!(matches!(exit, InterruptKind::Trap));
            assert_eq!(instance.program_counter(), Some(ProgramCounter(9)));
            assert_eq!(instance.reg(Reg::RA), 18);
            assert_eq!(instance.reg(Reg::from_raw(12).unwrap()), 0);
        } else {
            assert!(matches!(exit, InterruptKind::Finished));
            assert_eq!(instance.reg(Reg::RA), u64::from(polkavm::RETURN_TO_HOST));
            assert_eq!(instance.reg(Reg::from_raw(12).unwrap()), 18);
        }
    }
    assert_eq!(adapted, 22140);
    println!(
        "PolkaVM destination-byte cross-check passed: {count} rows, {adapted} scoped differences"
    );
}
