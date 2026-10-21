// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Check every dependent arithmetic result and block shortage through the pinned public engine.
// @@PvmReference={"input":"pvm-register-chains.bin","suite":"pvm_register_chain_reference"}
use polkavm::{
    CacheModel, CostModelKind, GasMeteringKind, InterruptKind, Module, ModuleConfig, ProgramBlob,
    ProgramCounter, ProgramParts, Reg,
};
use polkavm_common::program::InstructionSetKind;

// Fixed fields are read only after their entire enclosing structure has been bounded.
fn word(data: &[u8], at: usize, width: usize) -> u64 {
    let mut value = 0;
    for i in 0..width {
        value |= u64::from(data[at + i]) << (8 * i);
    }
    value
}

// Original fixture bytes and expected checkpoints are shared with the independent native consumer.
fn main() {
    let data = std::fs::read(std::env::args().nth(1).expect("provide PVMCHN01 corpus")).unwrap();
    assert!(data.len() >= 12 && &data[..8] == b"PVMCHN01" && word(&data, 8, 4) == 8);
    let engine = ragnarok_memory_probe::engine(true);
    let mut profile = ModuleConfig::new();
    profile.set_page_size(4096);
    profile.set_dynamic_paging(true);
    profile.set_gas_metering(Some(GasMeteringKind::Sync));
    profile.set_cost_model(Some(CostModelKind::Full(CacheModel::L2Hit)));
    let mut cursor = 12;
    for row in 0..8 {
        // Exact dimensions bound all offset arithmetic and allocations before field access.
        assert!(data.len() - cursor >= 116);
        let header = &data[cursor..cursor + 116];
        let length = word(header, 0, 4) as usize;
        assert_eq!(word(header, 4, 4), 5);
        assert_eq!(word(header, 8, 4), 85);
        cursor += 116;
        assert!(data.len() - cursor >= 100 + 85 * 120);
        let blocks = &data[cursor..cursor + 100];
        cursor += 100;
        let checks = &data[cursor..cursor + 85 * 120];
        cursor += 85 * 120;
        assert!((4..=2048).contains(&length) && length <= data.len() - cursor);
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = data[cursor..cursor + length].to_vec().into();
        cursor += length;
        let module =
            Module::from_blob(&engine, &profile, ProgramBlob::from_parts(parts).unwrap()).unwrap();
        let mut total = 0_u64;
        for block in 0..5 {
            // Both the public simulator and engine must agree with independently derived block prices.
            let start = word(blocks, block * 20, 4);
            let price = word(blocks, block * 20 + 4, 8);
            let cycles = word(blocks, block * 20 + 12, 8);
            assert!(start < 2048 && (1..10000).contains(&price) && (1..10000).contains(&cycles));
            assert_eq!(
                module.calculate_gas_cost_for(ProgramCounter(start as u32)),
                Some(price as i64)
            );
            total += price;
        }
        for scenario in 0_usize..7 {
            // Each execution starts from a fresh instance and the exact original register file.
            let blocked = scenario.saturating_sub(2);
            let budget = if scenario < 2 {
                total + if scenario == 0 { 7 } else { 0 }
            } else {
                (0..=blocked)
                    .map(|i| word(blocks, i * 20 + 4, 8))
                    .sum::<u64>()
                    - 1
            };
            let mut instance = module.instantiate().unwrap();
            for r in 0..13 {
                instance.set_reg(Reg::from_raw(r as u32).unwrap(), word(header, 12 + r * 8, 8));
            }
            instance.set_gas(budget as i64);
            instance.set_next_program_counter(ProgramCounter(0));
            let mut calls = 0;
            loop {
                // Each interruption must either match the next checkpoint or the selected terminal boundary.
                match instance.run().unwrap() {
                    InterruptKind::Ecalli(id) => {
                        assert_eq!(id, 13);
                        assert!(calls < 85, "row {row}: extra checkpoint");
                        let check = &checks[calls * 120..(calls + 1) * 120];
                        let pc = word(check, 0, 4);
                        let start = word(check, 4, 4);
                        let charge = word(check, 8, 8);
                        assert_eq!(start, word(blocks, (calls / 17) * 20, 4));
                        assert!(charge <= budget);
                        assert_eq!(instance.program_counter(), Some(ProgramCounter(pc as u32)));
                        assert_eq!(instance.gas(), (budget - charge) as i64);
                        for r in 0..13 {
                            assert_eq!(
                                instance.reg(Reg::from_raw(r as u32).unwrap()),
                                word(check, 16 + r * 8, 8),
                                "row {row}, checkpoint {calls}, register {r}"
                            );
                        }
                        calls += 1;
                    }
                    InterruptKind::Trap => {
                        assert!(scenario < 2);
                        assert_eq!(instance.gas(), (budget - total) as i64);
                        break;
                    }
                    InterruptKind::NotEnoughGas => {
                        assert!(scenario >= 2);
                        let start = word(blocks, blocked * 20, 4);
                        assert_eq!(instance.program_counter(), Some(ProgramCounter(start as u32)));
                        assert_eq!(instance.gas(), (word(blocks, blocked * 20 + 4, 8) - 1) as i64);
                        break;
                    }
                    other => panic!("row {row}: unexpected {other:?}"),
                }
            }
            let expected_calls = if scenario < 2 { 85 } else { blocked * 17 };
            assert_eq!(calls, expected_calls);
            for r in 0..13 {
                // Terminal registers retain precisely the last completed checkpoint, including refused prefixes.
                let expected = if calls == 0 {
                    word(header, 12 + r * 8, 8)
                } else {
                    word(checks, (calls - 1) * 120 + 16 + r * 8, 8)
                };
                assert_eq!(instance.reg(Reg::from_raw(r as u32).unwrap()), expected);
            }
        }
    }
    assert_eq!(cursor, data.len());
    println!("PolkaVM dependent register chains passed: 8 programs, 56 gas scenarios");
}
