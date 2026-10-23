// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Prepare and measure the fixed real guest through pinned public interpreted JamV1 APIs.
use polkavm::{
    BackendKind, CacheModel, Config, CostModelKind, Engine, GasMeteringKind, InterruptKind, Module,
    ModuleConfig, ProgramBlob, ProgramParts, RawInstance, Reg,
};
use std::{fs, path::Path, time::Instant};

const GAS: i64 = 1_000_000_000_000;

// A failed OS clock or invalid duration must never produce a successful timing row.
fn cpu_nanoseconds() -> u128 {
    let mut value = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    assert_eq!(
        unsafe { libc::clock_gettime(libc::CLOCK_PROCESS_CPUTIME_ID, &mut value) },
        0
    );
    assert!(value.tv_sec >= 0 && (0..1_000_000_000).contains(&value.tv_nsec));
    (value.tv_sec as u128)
        .checked_mul(1_000_000_000)
        .unwrap()
        .checked_add(value.tv_nsec as u128)
        .unwrap()
}

// Independently tabulated observable counts also bind the guest's checked export.
fn expected(limit: u32) -> u64 {
    match limit {
        100 => 25,
        1000 => 168,
        10000 => 1229,
        100000 => 9592,
        1000000 => 78498,
        10000000 => 664579,
        _ => panic!("unsupported validated sieve size"),
    }
}

// Backend selection is mandatory; no compiler fallback or alternative cost model is accepted.
fn module(blob: ProgramBlob) -> Module {
    let mut config = Config::default();
    config.set_backend(Some(BackendKind::Interpreter));
    let engine = Engine::new(&config).unwrap();
    assert_eq!(engine.backend(), BackendKind::Interpreter);
    let mut profile = ModuleConfig::default();
    profile.set_page_size(4096);
    profile.set_gas_metering(Some(GasMeteringKind::Sync));
    profile.set_cost_model(Some(CostModelKind::Full(CacheModel::L2Hit)));
    Module::from_blob(&engine, &profile, blob).unwrap()
}

// Initial and final memory observe exactly the same bounded declared page set in both engines.
fn pages(module: &Module) -> Vec<(u32, u8)> {
    let map = module.memory_map();
    let mut result = Vec::new();
    for (range, permission) in [
        (map.ro_data_range(), 1),
        (map.rw_data_range(), 2),
        (map.stack_range(), 2),
    ] {
        for address in range.step_by(4096) {
            result.push((address, permission));
        }
    }
    result.sort_by_key(|page| page.0);
    assert!(!result.is_empty() && result.len() <= 4096);
    assert!(result.windows(2).all(|pair| pair[0].0 < pair[1].0));
    result
}

// Each fresh instance receives all thirteen registers and the same finite gas supply before timing.
fn instance(module: &Module, entry: polkavm::ProgramCounter, registers: &[u64; 13]) -> RawInstance {
    let mut instance = module.instantiate().unwrap();
    for (index, value) in registers.iter().enumerate() {
        instance.set_reg(Reg::from_raw(index as u32).unwrap(), *value);
    }
    instance.set_gas(GAS);
    instance.set_next_program_counter(entry);
    instance
}

// Snapshot validation includes complete gas/register/mapped-memory outcomes, outside either clock.
fn snapshot(instance: &mut RawInstance, pages: &[(u32, u8)], limit: u32) -> Vec<u8> {
    assert_eq!(instance.reg(Reg::A0), expected(limit));
    assert!(instance.gas() >= 0);
    let mut result = b"PVMSIE01".to_vec();
    result.extend_from_slice(&(instance.gas() as u64).to_le_bytes());
    for index in 0..13 {
        result.extend_from_slice(&instance.reg(Reg::from_raw(index).unwrap()).to_le_bytes());
    }
    for &(address, _) in pages {
        result.extend_from_slice(&instance.read_memory(address, 4096).unwrap());
    }
    assert_eq!(result.len(), 120 + pages.len() * 4096);
    result
}

// Bounded explicit commands separate reference preparation from immutable measured inputs/results.
pub fn command(args: &[String]) {
    assert_eq!(args.len(), 5);
    let preparing = args[0] == "--sieve-prepare";
    assert!(preparing || args[0] == "--sieve");
    let artifact = Path::new(&args[1]);
    let output = Path::new(&args[2]);
    let limit: u32 = args[3].parse().unwrap();
    let samples: usize = args[4].parse().unwrap();
    expected(limit);
    assert!(samples == 1 || samples == 13);
    if std::env::var("RAGNAROK_PVM_SIEVE_ASSERT_PROBE").as_deref() == Ok("1") {
        panic!("pvm sieve reference assertion control");
    }
    let raw = fs::read(artifact).unwrap();
    assert!(!raw.is_empty() && raw.len() <= 4 * 1024 * 1024);
    let parts = ProgramParts::from_bytes(raw.clone().into()).unwrap();
    let blob = ProgramBlob::parse(raw.into()).unwrap();
    let entry = blob
        .exports()
        .find(|export| export == "run_checked")
        .unwrap()
        .program_counter();
    let module = module(blob);
    let mapped = pages(&module);
    let mut registers = [0; 13];
    registers[0] = 0xffff0000;
    registers[1] = u64::from(module.memory_map().stack_address_high());
    registers[7] = u64::from(limit);
    assert!(
        !parts.code_and_jump_table.is_empty() && parts.code_and_jump_table.len() <= 4 * 1024 * 1024
    );
    let mut initial = module.instantiate().unwrap();
    let mut input = b"PVMSIV01".to_vec();
    input.extend_from_slice(
        &u32::try_from(parts.code_and_jump_table.len())
            .unwrap()
            .to_le_bytes(),
    );
    input.extend_from_slice(&entry.0.to_le_bytes());
    input.extend_from_slice(&limit.to_le_bytes());
    input.extend_from_slice(&u32::try_from(mapped.len()).unwrap().to_le_bytes());
    input.extend_from_slice(&(GAS as u64).to_le_bytes());
    for value in registers {
        input.extend_from_slice(&value.to_le_bytes());
    }
    input.extend_from_slice(parts.code_and_jump_table.as_ref());
    for &(address, permission) in &mapped {
        input.extend_from_slice(&(address / 4096).to_le_bytes());
        input.push(permission);
        input.extend_from_slice(&initial.read_memory(address, 4096).unwrap());
    }
    let input_path = output.join(format!("input-{limit}.bin"));
    let expected_path = output.join(format!("expected-{limit}.bin"));
    if preparing {
        // Preparation runs once without timing; measured processes never regenerate a tampered expected value.
        fs::create_dir_all(output).unwrap();
        let mut instance = instance(&module, entry, &registers);
        assert_eq!(instance.run().unwrap(), InterruptKind::Finished);
        fs::write(input_path, input).unwrap();
        fs::write(expected_path, snapshot(&mut instance, &mapped, limit)).unwrap();
        println!(
            "SIEVE_PREPARED,{limit},{},{}",
            mapped.len(),
            parts.code_and_jump_table.len()
        );
        return;
    }
    assert_eq!(
        fs::read(input_path).unwrap(),
        input,
        "sieve input differs from artifact/ABI"
    );
    let reference = fs::read(expected_path).unwrap();
    assert_eq!(reference.len(), 120 + mapped.len() * 4096);
    for sample in 0..samples {
        let mut instance = instance(&module, entry, &registers);
        let wall = Instant::now();
        let cpu = cpu_nanoseconds();
        let result = instance.run().unwrap();
        let cpu_elapsed = cpu_nanoseconds() - cpu;
        let elapsed = wall.elapsed().as_nanos();
        assert_eq!(result, InterruptKind::Finished);
        assert_eq!(
            snapshot(&mut instance, &mapped, limit),
            reference,
            "sieve terminal state mismatch"
        );
        println!("SIEVE,polkavm_interpreter,{limit},{sample},{elapsed},{cpu_elapsed}");
    }
}
