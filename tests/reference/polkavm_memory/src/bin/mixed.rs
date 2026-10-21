// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Execute whole guest loops with memory, host replies, branches and exact/underfunded gas.
// @@PvmReference={"input":"pvm-mixed-program.bin","suite":"pvm_mixed_program_reference"}
use polkavm::{
    BackendKind, CacheModel, Config, CostModelKind, Engine, GasMeteringKind, InterruptKind,
    MemoryProtection, Module, ModuleConfig, ProgramBlob, ProgramCounter, ProgramParts, Reg,
};
use polkavm_common::program::InstructionSetKind;

// Decode fixed corpus fields after proving their enclosing 268-byte header is present.
fn word(data: &[u8], at: usize, width: usize) -> u64 {
    let mut value = 0;
    for i in 0..width {
        value |= u64::from(data[at + i]) << (8 * i);
    }
    value
}

fn main() {
    let data = std::fs::read(std::env::args().nth(1).expect("provide PVMMIX01 corpus")).unwrap();
    assert!(data.len() >= 12 && &data[..8] == b"PVMMIX01");
    assert_eq!(word(&data, 8, 4), 32);
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
    for row in 0..32 {
        assert!(data.len() - cursor >= 268);
        let h = &data[cursor..cursor + 268];
        let length = word(h, 0, 4) as usize;
        let iterations = word(h, 4, 4);
        let address = word(h, 8, 4) as u32;
        let initial = word(h, 12, 8);
        let body_price = word(h, 28, 8);
        let halt_price = word(h, 44, 8);
        assert!((1..=31).contains(&iterations) && matches!(address, 0x10000 | 0x10fff));
        assert!(body_price > 0 && body_price < 1000 && halt_price > 0 && halt_price < 1000);
        cursor += 268;
        assert!(length >= 4 && length <= 64 && length <= data.len() - cursor);
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = data[cursor..cursor + length].to_vec().into();
        cursor += length;
        let module =
            Module::from_blob(&engine, &profile, ProgramBlob::from_parts(parts).unwrap()).unwrap();
        assert_eq!(
            module.calculate_gas_cost_for(ProgramCounter(0)),
            Some(body_price as i64)
        );
        assert_eq!(
            module.calculate_gas_cost_for(ProgramCounter(20)),
            Some(halt_price as i64)
        );
        let total = iterations * body_price + halt_price;
        for scenario in 0..4 {
            // Every scenario owns its initial memory and CPU; previous hosts cannot leak state into it.
            let budget = match scenario {
                0 => total + 7,
                1 => total,
                2 => total - 1,
                _ => body_price - 1,
            };
            let mut instance = module.instantiate().unwrap();
            instance
                .zero_memory_with_memory_protection(0x10000, 8192, MemoryProtection::ReadWrite)
                .unwrap();
            let mut original = vec![33_u8; 8192];
            let at = (address - 0x10000) as usize;
            original[at..at + 8].copy_from_slice(&initial.to_le_bytes());
            instance.write_memory(0x10000, &original).unwrap();
            for i in 0..13 {
                instance.set_reg(Reg::from_raw(i as u32).unwrap(), word(h, 60 + i * 8, 8));
            }
            instance.set_gas(budget as i64);
            instance.set_next_program_counter(ProgramCounter(0));
            let mut calls = 0_u64;
            loop {
                // Explicit host bounds prevent a malformed branch from hanging the reference check.
                match instance.run().unwrap() {
                    InterruptKind::Ecalli(id) => {
                        assert!(calls < 2 * iterations, "row {row}: extra host");
                        let iteration = calls / 2;
                        let prior = initial.wrapping_add(iteration);
                        assert_eq!(
                            instance.gas(),
                            (budget - (iteration + 1) * body_price) as i64
                        );
                        assert_eq!(instance.reg(Reg::from_raw(10).unwrap()), iteration);
                        let bytes = instance.read_memory(address, 8).unwrap();
                        let value = u64::from_le_bytes(bytes.try_into().unwrap());
                        if calls % 2 == 0 {
                            assert_eq!(id, 13);
                            assert_eq!(instance.program_counter(), Some(ProgramCounter(3)));
                            assert_eq!(value, prior);
                            assert_eq!(instance.reg(Reg::A0), prior);
                            instance.set_reg(Reg::A0, prior.wrapping_add(1));
                        } else {
                            assert_eq!(id, 14);
                            assert_eq!(instance.program_counter(), Some(ProgramCounter(8)));
                            assert_eq!(value, prior.wrapping_add(1));
                            assert_eq!(instance.reg(Reg::A0), value);
                            let sum = instance.reg(Reg::A1).wrapping_add(value);
                            instance.set_reg(Reg::A1, sum);
                        }
                        calls += 1;
                    }
                    InterruptKind::Finished => {
                        assert!(scenario < 2);
                        break;
                    }
                    InterruptKind::NotEnoughGas => {
                        assert!(scenario >= 2);
                        assert_eq!(
                            instance.program_counter(),
                            Some(ProgramCounter(if scenario == 2 { 20 } else { 0 }))
                        );
                        break;
                    }
                    other => panic!("row {row}: {other:?}"),
                }
            }
            let completed = scenario != 3;
            assert_eq!(calls, if completed { 2 * iterations } else { 0 });
            assert_eq!(
                instance.gas(),
                if scenario < 2 {
                    (budget - total) as i64
                } else if scenario == 2 {
                    (halt_price - 1) as i64
                } else {
                    budget as i64
                }
            );
            for i in 0..13 {
                assert_eq!(
                    instance.reg(Reg::from_raw(i as u32).unwrap()),
                    word(h, if completed { 164 + i * 8 } else { 60 + i * 8 }, 8),
                    "row {row} reg {i}"
                );
            }
            let expected = if completed { word(h, 20, 8) } else { initial };
            original[at..at + 8].copy_from_slice(&expected.to_le_bytes());
            assert_eq!(instance.read_memory(0x10000, 8192).unwrap(), original);
        }
    }
    assert_eq!(cursor, data.len());
    println!("PolkaVM mixed-program cross-check passed: 32 programs, 128 gas scenarios");
}
