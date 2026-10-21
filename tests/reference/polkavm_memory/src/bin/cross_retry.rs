// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Metered missing-page/read-only repair and retry across all multi-byte scalar store forms.
// @@PvmReference={"input":"pvm-cross-page-retry.bin","suite":"pvm_metered_cross_page_retry"}
use polkavm::{
    BackendKind, CacheModel, Config, CostModelKind, Engine, GasMeteringKind, InterruptKind,
    MemoryProtection, Module, ModuleConfig, ProgramBlob, ProgramCounter, ProgramParts, Reg,
};
use polkavm_common::program::InstructionSetKind;

// Decode fixed fields after the enclosing 250-byte header extent has been proved.
fn word(data: &[u8], at: usize, width: usize) -> u64 {
    let mut value = 0;
    for i in 0..width {
        value |= u64::from(data[at + i]) << (8 * i);
    }
    value
}

fn main() {
    let data = std::fs::read(std::env::args().nth(1).expect("provide PVMCRY01 corpus")).unwrap();
    assert!(data.len() >= 12 && &data[..8] == b"PVMCRY01");
    assert_eq!(word(&data, 8, 4), 48);
    let mut config = Config::default();
    config.set_backend(Some(BackendKind::Interpreter));
    config.set_allow_dynamic_paging(true);
    let engine = Engine::new(&config).unwrap();
    let mut profile = ModuleConfig::new();
    profile.set_page_size(4096);
    profile.set_dynamic_paging(true);
    profile.set_gas_metering(Some(GasMeteringKind::Sync));
    profile.set_cost_model(Some(CostModelKind::Full(CacheModel::L2Hit)));
    let mut cursor = 12;
    for row in 0..48 {
        assert!(data.len() - cursor >= 250);
        let header = &data[cursor..cursor + 250];
        let length = word(header, 0, 4) as usize;
        let address = word(header, 9, 4) as usize;
        let width = header[13] as usize;
        let seed = header[16] as usize;
        assert!(matches!(width, 2 | 4 | 8) && address < 0x11000 && address + width > 0x11000);
        assert_eq!(&header[14..16], &[2, 0]);
        assert_eq!(word(header, 5, 4), 0x10000); // Original GP fault is deliberately retained.
        assert_eq!(word(header, 234, 8), 25);
        assert_eq!(word(header, 242, 8), 28);
        cursor += 250;
        assert!(length >= 4 && length <= 32 && length <= data.len() - cursor);
        let wire = &data[cursor..cursor + length];
        cursor += length;
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = wire.to_vec().into();
        let module =
            Module::from_blob(&engine, &profile, ProgramBlob::from_parts(parts).unwrap()).unwrap();
        assert_eq!(module.calculate_gas_cost_for(ProgramCounter(0)), Some(25));
        for budget in [25_i64, 32] {
            // Each budget owns an independent instance; a prior repaired run supplies no hidden state.
            let mut instance = module.instantiate().unwrap();
            instance
                .zero_memory_with_memory_protection(0x10000, 4096, MemoryProtection::ReadWrite)
                .unwrap();
            let original: Vec<u8> = (0..8192)
                .map(|i| ((i * 37 + seed) ^ (i >> 4)) as u8)
                .collect();
            instance.write_memory(0x10000, &original[..4096]).unwrap();
            instance.protect_memory(0x10000, 4096).unwrap();
            for i in 0..13 {
                instance.set_reg(
                    Reg::from_raw(i as u32).unwrap(),
                    word(header, 26 + i * 8, 8),
                );
            }
            instance.set_next_program_counter(ProgramCounter(0));
            instance.set_gas(24);
            // Underfunding wins before either page fault and retains the entire gas balance.
            assert!(
                matches!(instance.run().unwrap(), InterruptKind::NotEnoughGas),
                "row {row}"
            );
            assert_eq!(instance.gas(), 24);
            instance.set_gas(budget);
            for stage in 0..2 {
                // Missing higher page is repaired first, then the existing lower read-only page.
                match instance.run().unwrap() {
                    InterruptKind::Segfault(fault) => {
                        assert_eq!(
                            fault.page_address,
                            if stage == 0 { 0x11000 } else { 0x10000 }
                        );
                        assert_eq!(fault.is_write_protected, stage == 1);
                    }
                    other => panic!("row {row} stage {stage}: {other:?}"),
                }
                assert_eq!(instance.gas(), budget - 25);
                assert_eq!(instance.program_counter(), Some(ProgramCounter(0)));
                assert_eq!(
                    instance.read_memory(0x10000, 4096).unwrap(),
                    original[..4096]
                );
                for i in 0..13 {
                    assert_eq!(
                        instance.reg(Reg::from_raw(i as u32).unwrap()),
                        word(header, 26 + i * 8, 8)
                    );
                }
                if stage == 0 {
                    instance
                        .zero_memory_with_memory_protection(
                            0x11000,
                            4096,
                            MemoryProtection::ReadWrite,
                        )
                        .unwrap();
                    instance.write_memory(0x11000, &original[4096..]).unwrap();
                } else {
                    assert_eq!(
                        instance.read_memory(0x11000, 4096).unwrap(),
                        original[4096..]
                    );
                    instance.unprotect_memory(0x10000, 4096).unwrap();
                }
            }
            assert!(matches!(instance.run().unwrap(), InterruptKind::Trap));
            assert_eq!(instance.gas(), budget - 25);
            assert_eq!(
                instance.program_counter(),
                Some(ProgramCounter(u32::from(wire[2]) - 1))
            );
            for i in 0..13 {
                assert_eq!(
                    instance.reg(Reg::from_raw(i as u32).unwrap()),
                    word(header, 130 + i * 8, 8)
                );
            }
            let final_bytes = instance.read_memory(0x10000, 8192).unwrap();
            for (index, actual) in final_bytes.iter().enumerate() {
                // Only the final successful retry may write the independently frozen scalar bytes.
                let absolute = 0x10000 + index;
                let expected = if absolute >= address && absolute - address < width {
                    header[18 + absolute - address]
                } else {
                    original[index]
                };
                assert_eq!(*actual, expected, "row {row}, byte {index}");
            }
        }
    }
    assert_eq!(cursor, data.len());
    println!("PolkaVM metered cross-page repair passed: 48 rows, 96 budget/repair sequences");
}
