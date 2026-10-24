// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Link the pinned upstream sieve for JAM, export identical inputs, and validate PolkaVM runs.
use polkavm::{
    BackendKind, CacheModel, Config, CostModelKind, Engine, GasMeteringKind, InterruptKind, Module,
    ModuleConfig, ProgramBlob, ProgramParts, Reg,
};
use polkavm_linker::TargetInstructionSet;
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;
use std::time::Instant;

const GAS: i64 = 1_000_000_000_000;

// Use the platform header bindings from the already-pinned libc dependency.
fn cpu_nanoseconds() -> u128 {
    let mut value = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    assert_eq!(
        unsafe { libc::clock_gettime(libc::CLOCK_PROCESS_CPUTIME_ID, &mut value) },
        0
    );
    value.tv_sec as u128 * 1_000_000_000 + value.tv_nsec as u128
}

// Prime counts are independently tabulated, rather than obtained from another timed engine.
fn expected(limit: u32) -> u64 {
    match limit {
        100 => 25,
        1000 => 168,
        10000 => 1229,
        100000 => 9592,
        1000000 => 78498,
        10000000 => 664579,
        _ => panic!("unsupported validated size"),
    }
}

// Build only the interpreter; the pinned native backend targets x86-64, not this ARM host.
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

// Three explicit mapped ranges give the Nim engines exactly PolkaVM's initial memory image.
fn pages(module: &Module) -> Vec<(u32, u8)> {
    let map = module.memory_map();
    let mut pages = Vec::new();
    for (range, permission) in [
        (map.ro_data_range(), 1),
        (map.rw_data_range(), 2),
        (map.stack_range(), 2),
    ] {
        for address in range.step_by(4096) {
            pages.push((address, permission));
        }
    }
    pages.sort_by_key(|p| p.0);
    pages
}

// Each engine receives the same thirteen initial registers, not engine-specific call helpers.
fn registers(module: &Module, limit: u32) -> [u64; 13] {
    let mut registers = [0; 13];
    registers[0] = 0xffff0000;
    registers[1] = u64::from(module.memory_map().stack_address_high());
    registers[7] = u64::from(limit);
    registers
}

// Link through the pinned public linker API; no upstream source or runtime patch is applied.
fn link(elf: &Path, output: &Path) {
    fs::create_dir_all(output).unwrap();
    let bytes = polkavm_linker::program_from_elf(
        polkavm_linker::Config::default(),
        TargetInstructionSet::JamV1,
        &fs::read(elf).unwrap(),
    )
    .unwrap();
    fs::write(output.join("sieve.polkavm"), &bytes).unwrap();
    let parts = ProgramParts::from_bytes(bytes.clone().into()).unwrap();
    fs::write(
        output.join("program.bin"),
        parts.code_and_jump_table.as_ref(),
    )
    .unwrap();
    let blob = ProgramBlob::parse(bytes.into()).unwrap();
    let entry = blob
        .exports()
        .find(|e| e == "run_checked")
        .unwrap()
        .program_counter()
        .0;
    let mut inventory = BTreeMap::new();
    let mut count = 0;
    for instruction in blob.instructions() {
        if (instruction.offset.0 as usize) < blob.code().len() {
            let opcode = blob.code()[instruction.offset.0 as usize];
            *inventory.entry(opcode).or_insert(0usize) += 1;
            count += 1;
        }
    }
    let opcode_json = inventory
        .iter()
        .map(|(k, v)| format!("\"{k}\":{v}"))
        .collect::<Vec<_>>()
        .join(",");
    let module = module(blob.clone());
    fs::write(output.join("inventory.json"), format!(
        "{{\"entry\":{entry},\"code_bytes\":{},\"instructions\":{count},\"pages\":{},\"opcodes\":{{{opcode_json}}}}}\n",
        blob.code().len(), pages(&module).len())).unwrap();
    println!(
        "linked: {} code bytes, {count} instructions, {} opcodes",
        blob.code().len(),
        inventory.len()
    );
}

// Export one independently checked reference result, then time fresh identical invocations.
fn run(path: &Path, output: &Path, limit: u32, samples: usize) {
    let raw = fs::read(path).unwrap();
    let parts = ProgramParts::from_bytes(raw.clone().into()).unwrap();
    let blob = ProgramBlob::parse(raw.into()).unwrap();
    let entry = blob
        .exports()
        .find(|e| e == "run_checked")
        .unwrap()
        .program_counter();
    let module = module(blob);
    let pages = pages(&module);
    let registers = registers(&module, limit);
    let mut initial = module.instantiate().unwrap();
    let mut fixture = b"PVMSIV01".to_vec();
    fixture.extend_from_slice(&(parts.code_and_jump_table.len() as u32).to_le_bytes());
    fixture.extend_from_slice(&entry.0.to_le_bytes());
    fixture.extend_from_slice(&limit.to_le_bytes());
    fixture.extend_from_slice(&(pages.len() as u32).to_le_bytes());
    fixture.extend_from_slice(&(GAS as u64).to_le_bytes());
    for value in registers {
        fixture.extend_from_slice(&value.to_le_bytes());
    }
    fixture.extend_from_slice(parts.code_and_jump_table.as_ref());
    for &(address, permission) in &pages {
        fixture.extend_from_slice(&(address / 4096).to_le_bytes());
        fixture.push(permission);
        fixture.extend_from_slice(&initial.read_memory(address, 4096).unwrap());
    }
    fs::write(output.join(format!("input-{limit}.bin")), fixture).unwrap();
    let mut reference = Vec::new();
    for sample in 0..samples {
        let mut instance = module.instantiate().unwrap();
        for (i, value) in registers.iter().enumerate() {
            instance.set_reg(Reg::from_raw(i as u32).unwrap(), *value);
        }
        instance.set_gas(GAS);
        instance.set_next_program_counter(entry);
        let start = Instant::now();
        let cpu_start = cpu_nanoseconds();
        let result = instance.run().unwrap();
        let cpu_elapsed = cpu_nanoseconds() - cpu_start;
        let elapsed = start.elapsed().as_nanos();
        assert_eq!(result, InterruptKind::Finished);
        assert_eq!(instance.reg(Reg::A0), expected(limit));
        let mut observed = b"PVMSIE01".to_vec();
        observed.extend_from_slice(&(instance.gas() as u64).to_le_bytes());
        for i in 0..13 {
            observed.extend_from_slice(&instance.reg(Reg::from_raw(i).unwrap()).to_le_bytes());
        }
        for &(address, _) in &pages {
            observed.extend_from_slice(&instance.read_memory(address, 4096).unwrap());
        }
        if sample == 0 {
            reference = observed.clone();
            fs::write(output.join(format!("expected-{limit}.bin")), &reference).unwrap();
        } else {
            assert_eq!(observed, reference);
        }
        println!("SIEVE,polkavm,{limit},{sample},{elapsed},{cpu_elapsed}");
    }
}

fn main() {
    let args: Vec<_> = std::env::args().collect();
    match args[1].as_str() {
        "link" => link(Path::new(&args[2]), Path::new(&args[3])),
        "run" => run(
            Path::new(&args[2]),
            Path::new(&args[3]),
            args[4].parse().unwrap(),
            args[5].parse().unwrap(),
        ),
        _ => panic!("link/run required"),
    }
}
