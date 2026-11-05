// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Measure execution after setup, then validate complete outcomes outside the timed region.
use polkavm::{
    BackendKind, CacheModel, Config, CostModelKind, Engine, GasMeteringKind, InterruptKind,
    MemoryProtection, Module, ModuleConfig, ProgramBlob, ProgramCounter, ProgramParts, Reg,
};
use polkavm_common::program::InstructionSetKind;
use std::time::Instant;

mod sieve;

// Fixed scalar fields are read only after their enclosing record is checked.
fn word(data: &[u8], at: usize, width: usize) -> u64 {
    let mut result = 0;
    for i in 0..width {
        result |= u64::from(data[at + i]) << (8 * i);
    }
    result
}

#[path = "../../polkavm_backend.rs"]
mod measurement;

fn main() {
    if measurement::clock_control() {
        return;
    }
    let args: Vec<String> = std::env::args().collect();
    if args
        .get(1)
        .is_some_and(|arg| arg == "--sieve" || arg == "--sieve-prepare")
    {
        sieve::command(&args[1..]);
        return;
    }
    assert_eq!(args.len(), 3);
    let protocol = std::env::var("RAGNAROK_PVM_PERFORMANCE").unwrap_or_default();
    assert!(matches!(protocol.as_str(), "" | "0" | "1"));
    let modern = protocol == "1";
    if modern && std::env::var("RAGNAROK_PVM_BENCH_ASSERT_PROBE").as_deref() == Ok("1") {
        // The canonical runner must prove optimized reference assertions remain active.
        panic!("pvm synthetic reference assertion control");
    }
    let backend = match args[2].as_str() {
        "interpreter" => BackendKind::Interpreter,
        "compiler" => BackendKind::Compiler,
        _ => panic!("explicit backend required"),
    };
    assert_eq!(measurement::selected(backend), backend);
    if modern {
        // This protocol has exactly one denominator; optional compiled-clock records belong elsewhere.
        assert_eq!(backend, BackendKind::Interpreter);
        assert!(
            !measurement::explicit(),
            "synthetic reference override is forbidden"
        );
    }
    let data = std::fs::read(&args[1]).unwrap();
    assert!(data.len() >= 12 && &data[..8] == b"PVMBEN01");
    assert_eq!(word(&data, 8, 4), 11);
    let mut cursor = 12;
    for row in 0..11 {
        assert!(data.len() - cursor >= 273);
        let h = &data[cursor..cursor + 273];
        let length = word(h, 0, 4) as usize;
        let kind = h[4];
        let iterations = word(h, 5, 4);
        let address = word(h, 9, 4) as u32;
        let price = word(h, 29, 8);
        let halt = word(h, 45, 4) as u32;
        let halt_price = word(h, 49, 8);
        assert!(kind <= 5 && iterations > 0 && iterations <= 10000);
        assert!(price > 0 && price < 1000 && halt_price > 0 && halt_price < 1000);
        let second_price = if kind == 5 { word(h, 13, 8) } else { 0 };
        if kind == 5 {
            // Memoryless alternating records specify the second block PC/price in auxiliary slots.
            assert!(address == 8 && second_price > 0 && second_price < 1000);
        }
        cursor += 273;
        assert!(length >= 4 && length <= 128 && length <= data.len() - cursor);
        let wire = &data[cursor..cursor + length];
        cursor += length;
        let preparation = Instant::now();
        let preparation_cpu = measurement::process_cpu();
        let mut config = Config::default();
        config.set_backend(Some(backend));
        config.set_allow_dynamic_paging(matches!(kind, 1 | 2 | 4));
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
        profile.set_dynamic_paging(matches!(kind, 1 | 2 | 4));
        profile.set_gas_metering(Some(GasMeteringKind::Sync));
        profile.set_cost_model(Some(CostModelKind::Full(CacheModel::L2Hit)));
        let module =
            Module::from_blob(&engine, &profile, ProgramBlob::from_parts(parts).unwrap()).unwrap();
        let modern_preparation = if modern {
            // Constructor clocks stop before the independent gas oracles; publish only after they pass.
            let cpu = measurement::process_cpu() - preparation_cpu;
            Some((cpu, preparation.elapsed().as_nanos()))
        } else {
            // Historical wall-only observations retain their existing stop after the oracle checks.
            None
        };
        assert_eq!(
            module.calculate_gas_cost_for(ProgramCounter(0)),
            Some(price as i64)
        );
        assert_eq!(
            module.calculate_gas_cost_for(ProgramCounter(halt)),
            Some(halt_price as i64)
        );
        if kind == 5 {
            assert_eq!(
                module.calculate_gas_cost_for(ProgramCounter(address)),
                Some(second_price as i64)
            );
        }
        let prepare_ns = preparation.elapsed().as_nanos();
        let label = format!("synthetic-{row}");
        measurement::module_receipt(
            &label,
            engine.backend(),
            &module,
            measurement::process_cpu() - preparation_cpu,
        );
        if modern {
            // Bind actual engine/module identity and both real constructor clocks before sample zero.
            let (prepare_cpu_ns, prepare_wall_ns) = modern_preparation.unwrap();
            let machine_code_bytes = module.machine_code().map_or(0, |code| code.len());
            assert_eq!(engine.backend(), BackendKind::Interpreter);
            assert_eq!(machine_code_bytes, 0);
            assert!(prepare_cpu_ns > 0 && prepare_wall_ns > 0);
            println!("SYNTHETIC_PREPARE,1,{row},{prepare_cpu_ns},{prepare_wall_ns}");
            println!("SYNTHETIC_REFERENCE,1,{row},interpreter,interpreter,{machine_code_bytes}");
        }
        for sample in 0..13 {
            // Instantiation, input resets and register setup are excluded from execution time.
            let mut instance = module.instantiate().unwrap();
            let mut original = vec![33_u8; 8192];
            let pairs = if kind == 4 { 64 } else { 1 };
            if matches!(kind, 1 | 2 | 4) {
                assert!(matches!(address, 0x10000 | 0x10fff));
                let offset = (address - 0x10000) as usize;
                original[offset..offset + 8].copy_from_slice(&word(h, 13, 8).to_le_bytes());
                // Sparse cases contain exactly the same mapped pairs and holes as the native owner.
                for pair in 0..pairs {
                    let base = 0x10000 + pair * 16384;
                    instance
                        .zero_memory_with_memory_protection(base, 8192, MemoryProtection::ReadWrite)
                        .unwrap();
                    if pair == 0 {
                        instance.write_memory(base, &original).unwrap();
                    } else {
                        // Untouched pages carry independent canaries and are checked completely after execution.
                        instance.write_memory(base, &[33_u8; 8192]).unwrap();
                    }
                }
            }
            for i in 0..13 {
                instance.set_reg(Reg::from_raw(i as u32).unwrap(), word(h, 65 + i * 8, 8));
            }
            instance.set_gas((iterations * (price + second_price) + halt_price + 7) as i64);
            instance.set_next_program_counter(ProgramCounter(0));
            let mut calls = 0_u64;
            let cpu = measurement::CpuTimer::start(&instance);
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
            let cpu = cpu.finish();
            // Every warmup and measured execution must validate before a timing record is accepted.
            assert_eq!(instance.gas(), 7);
            assert_eq!(calls, if kind == 2 { 2 * iterations } else { 0 });
            for i in 0..13 {
                assert_eq!(
                    instance.reg(Reg::from_raw(i as u32).unwrap()),
                    word(h, 169 + i * 8, 8),
                    "pvm synthetic terminal register mismatch"
                );
            }
            if matches!(kind, 1 | 2 | 4) {
                let offset = (address - 0x10000) as usize;
                original[offset..offset + 8].copy_from_slice(&word(h, 21, 8).to_le_bytes());
                assert_eq!(instance.read_memory(0x10000, 8192).unwrap(), original);
                for pair in 1..pairs {
                    // Every mapped byte outside the scalar remains observable to the harness.
                    assert_eq!(
                        instance.read_memory(0x10000 + pair * 16384, 8192).unwrap(),
                        [33_u8; 8192]
                    );
                }
            }
            if kind == 4 {
                for pair in 0..64 {
                    // Sparse mapping holes must remain inaccessible after the measured execution.
                    assert!(instance.read_memory(0x12000 + pair * 16384, 4096).is_err());
                }
            }
            assert!(elapsed > 0);
            cpu.receipt(&label, sample);
            if modern {
                // CpuTimer's checked total is process CPU here; never relabel the legacy Instant delta.
                let cpu_ns = cpu.total;
                assert!(cpu_ns > 0);
                println!("SYNTHETIC_SAMPLE,1,{row},{sample},{cpu_ns},{elapsed}");
            } else {
                // Existing diagnostics continue to consume their unchanged wall-only sample format.
                println!("sample\t{row}\t{sample}\t{elapsed}\t{prepare_ns}");
            }
        }
    }
    assert_eq!(cursor, data.len());
    if modern {
        println!("SYNTHETIC_OK,1,reference");
    }
}
