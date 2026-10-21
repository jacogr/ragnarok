// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Measure execution after setup, then validate complete outcomes outside the timed region.
use polkavm::{
    BackendKind, CacheModel, Config, CostModelKind, Engine, GasMeteringKind, InterruptKind,
    MemoryProtection, Module, ModuleConfig, ProgramBlob, ProgramCounter, ProgramParts, Reg,
};
use polkavm_common::program::InstructionSetKind;
use std::time::Instant;

// Fixed scalar fields are read only after their enclosing record is checked.
fn word(data: &[u8], at: usize, width: usize) -> u64 {
    let mut result = 0;
    for i in 0..width {
        result |= u64::from(data[at + i]) << (8 * i);
    }
    result
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    assert_eq!(args.len(), 3);
    let backend = match args[2].as_str() {
        "interpreter" => BackendKind::Interpreter,
        "compiler" => BackendKind::Compiler,
        _ => panic!("explicit backend required"),
    };
    let data = std::fs::read(&args[1]).unwrap();
    assert!(data.len() >= 12 && &data[..8] == b"PVMBEN01");
    assert_eq!(word(&data, 8, 4), 5);
    let mut cursor = 12;
    for row in 0..5 {
        assert!(data.len() - cursor >= 273);
        let h = &data[cursor..cursor + 273];
        let length = word(h, 0, 4) as usize;
        let kind = h[4];
        let iterations = word(h, 5, 4);
        let address = word(h, 9, 4) as u32;
        let price = word(h, 29, 8);
        let halt = word(h, 45, 4) as u32;
        let halt_price = word(h, 49, 8);
        assert!(kind <= 2 && iterations > 0 && iterations <= 10000);
        assert!(price > 0 && price < 1000 && halt_price > 0 && halt_price < 1000);
        cursor += 273;
        assert!(length >= 4 && length <= 128 && length <= data.len() - cursor);
        let wire = &data[cursor..cursor + length];
        cursor += length;
        let preparation = Instant::now();
        let mut config = Config::default();
        config.set_backend(Some(backend));
        config.set_allow_dynamic_paging(kind != 0);
        let engine = match Engine::new(&config) {
            Ok(engine) => engine,
            Err(error) if backend == BackendKind::Compiler => {
                // Report an unavailable backend/profile, never an interpreter value in this column.
                println!(
                    "unavailable\t{row}\t{}",
                    error.to_string().replace(['\n', '\r', '\t'], " ")
                );
                continue;
            }
            Err(error) => panic!("required interpreter unavailable: {error}"),
        };
        assert_eq!(engine.backend(), backend);
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = wire.to_vec().into();
        let mut profile = ModuleConfig::new();
        profile.set_page_size(4096);
        profile.set_dynamic_paging(kind != 0);
        profile.set_gas_metering(Some(GasMeteringKind::Sync));
        profile.set_cost_model(Some(CostModelKind::Full(CacheModel::L2Hit)));
        let module =
            Module::from_blob(&engine, &profile, ProgramBlob::from_parts(parts).unwrap()).unwrap();
        assert_eq!(
            module.calculate_gas_cost_for(ProgramCounter(0)),
            Some(price as i64)
        );
        assert_eq!(
            module.calculate_gas_cost_for(ProgramCounter(halt)),
            Some(halt_price as i64)
        );
        let prepare_ns = preparation.elapsed().as_nanos();
        for sample in 0..13 {
            // Instantiation, input resets and register setup are excluded from execution time.
            let mut instance = module.instantiate().unwrap();
            let mut original = vec![33_u8; 8192];
            if kind != 0 {
                assert!(matches!(address, 0x10000 | 0x10fff));
                let offset = (address - 0x10000) as usize;
                original[offset..offset + 8].copy_from_slice(&word(h, 13, 8).to_le_bytes());
                instance
                    .zero_memory_with_memory_protection(0x10000, 8192, MemoryProtection::ReadWrite)
                    .unwrap();
                instance.write_memory(0x10000, &original).unwrap();
            }
            for i in 0..13 {
                instance.set_reg(Reg::from_raw(i as u32).unwrap(), word(h, 65 + i * 8, 8));
            }
            instance.set_gas((iterations * price + halt_price + 7) as i64);
            instance.set_next_program_counter(ProgramCounter(0));
            let mut calls = 0_u64;
            let start = Instant::now();
            loop {
                // Host dispatch/replies are part of embedding execution; validation stays outside timing.
                match instance.run().unwrap() {
                    InterruptKind::Finished => break,
                    InterruptKind::Ecalli(13) => {
                        let value = instance.reg(Reg::A0).wrapping_add(1);
                        instance.set_reg(Reg::A0, value);
                        calls += 1;
                    }
                    InterruptKind::Ecalli(14) => {
                        let sum = instance.reg(Reg::A1).wrapping_add(instance.reg(Reg::A0));
                        instance.set_reg(Reg::A1, sum);
                        calls += 1;
                    }
                    other => panic!("benchmark row {row}: unexpected {other:?}"),
                }
            }
            let elapsed = start.elapsed().as_nanos();
            // Every warmup and measured execution must validate before a timing record is accepted.
            assert_eq!(instance.gas(), 7);
            assert_eq!(calls, if kind == 2 { 2 * iterations } else { 0 });
            for i in 0..13 {
                assert_eq!(
                    instance.reg(Reg::from_raw(i as u32).unwrap()),
                    word(h, 169 + i * 8, 8)
                );
            }
            if kind != 0 {
                let offset = (address - 0x10000) as usize;
                original[offset..offset + 8].copy_from_slice(&word(h, 21, 8).to_le_bytes());
                assert_eq!(instance.read_memory(0x10000, 8192).unwrap(), original);
            }
            assert!(elapsed > 0);
            println!("sample\t{row}\t{sample}\t{elapsed}\t{prepare_ns}");
        }
    }
    assert_eq!(cursor, data.len());
}
