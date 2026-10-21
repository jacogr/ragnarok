// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Public Sync/Full/L2Hit fault-repair/retry observations for every direct scalar memory form.
// @@PvmReference={"suite":"pvm_metered_fault_retry_reference"}
use polkavm::{
    BackendKind, CacheModel, Config, CostModelKind, Engine, GasMeteringKind, InterruptKind,
    MemoryProtection, Module, ModuleConfig, ProgramBlob, ProgramCounter, ProgramParts, Reg,
};
use polkavm_common::program::InstructionSetKind;
fn main() {
    let mut config = Config::default();
    config.set_backend(Some(BackendKind::Interpreter));
    config.set_allow_dynamic_paging(true);
    let engine = Engine::new(&config).unwrap();
    let mut cases = 0;
    for op in 52_u8..=62 {
        for read_only in [false, true] {
            let wire = vec![
                0_u8, 0, 11, 51, 8, 11, op, 7, 255, 255, 255, 255, 50, 0, 9, 2,
            ];
            let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
            parts.code_and_jump_table = wire.into();
            let blob = ProgramBlob::from_parts(parts).unwrap();
            let mut profile = ModuleConfig::new();
            profile.set_page_size(4096);
            profile.set_dynamic_paging(true);
            profile.set_gas_metering(Some(GasMeteringKind::Sync));
            profile.set_cost_model(Some(CostModelKind::Full(CacheModel::L2Hit)));
            let module = Module::from_blob(&engine, &profile, blob).unwrap();
            assert_eq!(module.calculate_gas_cost_for(ProgramCounter(0)), Some(25));
            let mut instance = module.instantiate().unwrap();
            instance.set_reg(Reg::RA, polkavm::RETURN_TO_HOST);
            instance.set_reg(Reg::A0, 99);
            instance.set_reg(Reg::A1, 77);
            instance.set_gas(32);
            instance.set_next_program_counter(ProgramCounter(0));
            match instance.run().unwrap() {
                InterruptKind::Segfault(fault) => assert_eq!(fault.page_address, 0xfffff000),
                other => panic!("unexpected first exit {other:?}"),
            }
            assert_eq!(instance.gas(), 7);
            assert_eq!(instance.program_counter(), Some(ProgramCounter(3)));
            assert_eq!(instance.reg(Reg::A0), 99);
            assert_eq!(instance.reg(Reg::A1), 11);
            instance
                .zero_memory_with_memory_protection(0xfffff000, 4096, MemoryProtection::ReadWrite)
                .unwrap();
            instance.write_memory(0xfffff000, &[7; 4096]).unwrap();
            if read_only {
                instance.protect_memory(0xfffff000, 4096).unwrap();
            }
            assert!(matches!(instance.run().unwrap(), InterruptKind::Trap));
            assert_eq!(instance.gas(), 7);
            assert_eq!(instance.program_counter(), Some(ProgramCounter(3)));
            for index in 0..13 {
                let expected = match index {
                    0 => u64::from(polkavm::RETURN_TO_HOST),
                    7 => 99,
                    8 => 11,
                    _ => 0,
                };
                assert_eq!(instance.reg(Reg::from_raw(index).unwrap()), expected);
            }
            assert_eq!(instance.read_u8(0xfffffffe).unwrap(), 7);
            assert_eq!(instance.read_u8(0xffffffff).unwrap(), 7);
            cases += 1;
        }
    }
    println!("PolkaVM metered fault-repair/retry passed: {cases}; cost25 and remaining7");
}
