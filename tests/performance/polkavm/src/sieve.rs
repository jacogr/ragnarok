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

// A selected family remains fixed for preparation and every measured snapshot.
#[derive(Clone, Copy, PartialEq)]
enum Guest {
    Sieve,
    Minimal,
    Memset,
    Pinky,
}
impl Guest {
    // Reject unknown labels rather than interpreting another family's results as sieve.
    fn selected() -> Self {
        match std::env::var("RAGNAROK_PVM_GUEST").as_deref() {
            Err(_) | Ok("") | Ok("sieve") => Self::Sieve,
            Ok("minimal") => Self::Minimal,
            Ok("memset") => Self::Memset,
            Ok("pinky") => Self::Pinky,
            _ => panic!("unknown checked guest family"),
        }
    }
    // Stable protocol labels bind each complete process to one frozen artifact family.
    fn name(self) -> &'static str {
        match self {
            Self::Sieve => "sieve",
            Self::Minimal => "minimal",
            Self::Memset => "memset",
            Self::Pinky => "pinky",
        }
    }
}

// Independent mathematical results supplement complete state comparison for every guest.
fn expected(guest: Guest, limit: u32) -> u64 {
    match guest {
        Guest::Pinky => {
            // The frozen source is already initialized; the checked call converts one complete rendered frame.
            assert_eq!(limit, 1);
            1
        }
        Guest::Minimal => {
            assert!(limit == 1000 || limit == 100000);
            2 * u64::from(limit) + u64::from(limit % 2)
        }
        Guest::Memset => {
            assert!(limit == 1000 || limit == 100000);
            u64::from(limit - 1)
        }
        Guest::Sieve => match limit {
            100 => 25,
            1000 => 168,
            10000 => 1229,
            100000 => 9592,
            1000000 => 78498,
            10000000 => 664579,
            _ => panic!("unsupported validated sieve size"),
        },
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

// Restore writable initialized pages before timing; every run still owns a fresh public instance.
fn restored_instance(
    module: &Module,
    entry: polkavm::ProgramCounter,
    registers: &[u64; 13],
    images: &[(u32, Vec<u8>)],
) -> RawInstance {
    let mut fresh = instance(module, entry, registers);
    for (address, bytes) in images {
        // Public writes restore exact initialized RAM; read-only module pages are never changed.
        fresh.write_memory(*address, bytes).unwrap();
    }
    fresh
}

// Snapshot validation includes complete gas/register/mapped-memory outcomes, outside either clock.
fn snapshot(instance: &mut RawInstance, pages: &[(u32, u8)], guest: Guest, limit: u32) -> Vec<u8> {
    assert_eq!(instance.reg(Reg::A0), expected(guest, limit));
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
    let guest = Guest::selected();
    expected(guest, limit);
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
    // Pinky uses the same initialized NES state in both interpreters; its nine setup frames are untimed.
    let initialize = if guest == Guest::Pinky {
        Some(
            blob.exports()
                .find(|export| export == "initialize")
                .unwrap()
                .program_counter(),
        )
    } else {
        None
    };
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
    if let Some(entry) = initialize {
        // Initialize once per process, outside all execution clocks and before freezing mapped input bytes.
        initial = instance(&module, entry, &registers);
        assert_eq!(initial.run().unwrap(), InterruptKind::Finished);
    }
    let mut initialized_pages = Vec::new();
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
        let bytes = initial.read_memory(address, 4096).unwrap();
        input.extend_from_slice(&bytes);
        if guest == Guest::Pinky && permission == 2 {
            // The source snapshot includes heap, framebuffer and stack residues from the same initializer.
            initialized_pages.push((address, bytes));
        }
    }
    let input_path = output.join(format!("input-{limit}.bin"));
    let expected_path = output.join(format!("expected-{limit}.bin"));
    if preparing {
        // Preparation runs once without timing; measured processes never regenerate a tampered expected value.
        fs::create_dir_all(output).unwrap();
        let mut instance = restored_instance(&module, entry, &registers, &initialized_pages);
        assert_eq!(instance.run().unwrap(), InterruptKind::Finished);
        fs::write(input_path, input).unwrap();
        fs::write(
            expected_path,
            snapshot(&mut instance, &mapped, guest, limit),
        )
        .unwrap();
        if guest == Guest::Sieve {
            // Preserve the existing maintained sieve command's preparation framing.
            println!(
                "SIEVE_PREPARED,{limit},{},{}",
                mapped.len(),
                parts.code_and_jump_table.len()
            );
        } else {
            // Bind additional frozen guest preparations to their explicit selected family.
            println!(
                "GUEST_PREPARED,{},{limit},{},{}",
                guest.name(),
                mapped.len(),
                parts.code_and_jump_table.len()
            );
        }
        return;
    }
    // Compare complete images without dumping multi-megabyte byte arrays on a refused control.
    assert!(
        fs::read(input_path).unwrap() == input,
        "sieve input differs from artifact/ABI"
    );
    let reference = fs::read(expected_path).unwrap();
    assert_eq!(reference.len(), 120 + mapped.len() * 4096);
    if guest != Guest::Sieve {
        // A mandatory family prefix prevents cross-family sample relabeling.
        println!("GUEST,{}", guest.name());
    }
    for sample in 0..samples {
        let mut instance = restored_instance(&module, entry, &registers, &initialized_pages);
        let wall = Instant::now();
        let cpu = cpu_nanoseconds();
        let result = instance.run().unwrap();
        let cpu_elapsed = cpu_nanoseconds() - cpu;
        let elapsed = wall.elapsed().as_nanos();
        assert_eq!(result, InterruptKind::Finished);
        // Equality still covers every byte; a mismatch retains a bounded diagnostic instead of the arrays.
        assert!(
            snapshot(&mut instance, &mapped, guest, limit) == reference,
            "sieve terminal state mismatch"
        );
        println!("SIEVE,polkavm_interpreter,{limit},{sample},{elapsed},{cpu_elapsed}");
    }
}
