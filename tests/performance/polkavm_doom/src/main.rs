// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Prepare bounded DOOM snapshots and validate measured, explicitly selected reference backends.
use polkavm::{
    BackendKind, CacheModel, Config, CostModelKind, Engine, GasMeteringKind, InterruptKind, Module,
    ModuleConfig, ProgramBlob, ProgramCounter, ProgramParts, RawInstance, Reg,
};
use polkavm_common::program::{ISA_JamV1, InstructionSetKind};
use polkavm_common::utils::ArcBytes;
use std::{fs, path::Path};
#[path = "../../polkavm_backend.rs"]
mod measurement;
const GAS: i64 = 1_000_000_000_000;
const HOSTS: [&str; 5] = [
    "ext_output_audio",
    "ext_output_video",
    "ext_rom_read",
    "ext_rom_size",
    "ext_stdout",
];

// Keep generated framing independent of the production guest decoder and reject truncated fields.
fn word(bytes: &[u8], at: usize, width: usize) -> u64 {
    assert!(width <= 8 && at.checked_add(width).unwrap() <= bytes.len());
    let mut value = 0;
    for i in 0..width {
        value |= u64::from(bytes[at + i]) << (8 * i);
    }
    value
}

// Keep copied host payloads as owned records; serialization never enters guest collection/timing.
struct OutputEvent {
    kind: u8,
    bytes: Vec<u8>,
}
struct Events {
    records: Vec<OutputEvent>,
    length: usize,
}
impl Events {
    // Encode the independently checked output format only after the measured guest call returns.
    fn encode(&self) -> Vec<u8> {
        let mut data = Vec::with_capacity(self.length);
        for event in &self.records {
            data.push(event.kind);
            data.extend((event.bytes.len() as u32).to_le_bytes());
            data.extend_from_slice(&event.bytes);
        }
        assert_eq!(data.len(), self.length);
        data
    }
}

// One validated JamV1 blob fixes import identities, code, data and both public entry points.
struct Guest {
    module: Module,
    source_bytes: ArcBytes,
    wire: Vec<u8>,
    hosts: [u32; 5],
    entries: [ProgramCounter; 2],
    pages: Vec<(u32, u8)>,
    capture_events: bool,
}
impl Guest {
    // Force the interpreter and the same checked memory/cost model as the native embedding.
    fn load(path: &Path) -> Self {
        let mut guest = Self::from_bytes(fs::read(path).unwrap());
        guest.prepare_oracles();
        guest
    }

    // Cold canonical admission receives already-read bytes, never performs fixture IO.
    fn from_bytes(raw: Vec<u8>) -> Self {
        let source_bytes: ArcBytes = raw.into();
        let blob = ProgramBlob::parse(source_bytes.clone()).unwrap();
        assert_eq!(blob.isa(), InstructionSetKind::JamV1);
        blob.validate_code_with_isa(ISA_JamV1).unwrap();
        let hosts = HOSTS.map(|name| {
            blob.imports()
                .iter()
                .position(|x| x.unwrap() == name)
                .unwrap() as u32
        });
        assert_eq!(blob.imports().iter().count(), HOSTS.len());
        let entries = ["ext_initialize", "ext_tick"].map(|name| {
            blob.exports()
                .find(|x| x == name)
                .unwrap()
                .program_counter()
        });
        let mut config = Config::default();
        let backend = measurement::selected(BackendKind::Interpreter);
        config.set_backend(Some(backend));
        let engine = Engine::new(&config).unwrap();
        assert_eq!(engine.backend(), backend);
        let mut profile = ModuleConfig::default();
        profile.set_page_size(4096);
        profile.set_gas_metering(Some(GasMeteringKind::Sync));
        profile.set_cost_model(Some(CostModelKind::Full(CacheModel::L2Hit)));
        let cpu = measurement::process_cpu();
        let module = Module::from_blob(&engine, &profile, blob).unwrap();
        measurement::module_receipt(
            "doom",
            engine.backend(),
            &module,
            measurement::process_cpu() - cpu,
        );
        Self {
            module,
            source_bytes,
            wire: Vec::new(),
            hosts,
            entries,
            pages: Vec::new(),
            capture_events: true,
        }
    }
    // Independent fixture/code/map oracles are prepared externally, never during cold admission.
    fn prepare_oracles(&mut self) {
        assert!(self.wire.is_empty() && self.pages.is_empty());
        let parts = ProgramParts::from_bytes(self.source_bytes.clone()).unwrap();
        self.wire = parts.code_and_jump_table.to_vec();
        let map = self.module.memory_map();
        let mut pages = Vec::new();
        for (range, access) in [
            (map.ro_data_range(), 1),
            (map.rw_data_range(), 2),
            (map.stack_range(), 2),
        ] {
            // Only the module's declared readable ranges enter the complete shared state.
            for address in range.step_by(4096) {
                pages.push((address, access));
            }
        }
        pages.sort();
        assert!(!pages.is_empty() && pages.len() <= 8192);
        assert!(pages.windows(2).all(|x| x[0].0 < x[1].0));
        self.pages = pages;
    }
    // Reset one external call's complete ABI without changing retained guest memory.
    fn reset(&self, instance: &mut RawInstance, phase: usize) {
        for index in 0..13 {
            instance.set_reg(Reg::from_raw(index).unwrap(), 0);
        }
        instance.set_reg(Reg::RA, 0xffff0000);
        instance.set_reg(
            Reg::SP,
            u64::from(self.module.memory_map().stack_address_high()),
        );
        instance.set_next_program_counter(self.entries[phase]);
        instance.set_gas(GAS);
    }
    // Full initial bytes and permissions are shared, including stack residues after warmup.
    fn input(&self, instance: &mut RawInstance, phase: usize) -> Vec<u8> {
        let mut out = b"PVMDOM01".to_vec();
        for value in [
            self.wire.len() as u32,
            self.entries[phase].0,
            self.pages.len() as u32,
        ] {
            out.extend(value.to_le_bytes());
        }
        for value in self.hosts {
            out.extend(value.to_le_bytes());
        }
        out.extend((GAS as u64).to_le_bytes());
        for index in 0..13 {
            out.extend(instance.reg(Reg::from_raw(index).unwrap()).to_le_bytes());
        }
        assert_eq!(out.len(), 152);
        out.extend(&self.wire);
        for &(address, access) in &self.pages {
            // Capture exactly one canonical page record for every mapped page.
            out.extend((address / 4096).to_le_bytes());
            out.push(access);
            out.extend(instance.read_memory(address, 4096).unwrap());
        }
        out
    }
    // Return complete terminal registers/gas/memory; no framebuffer-only result can pass.
    fn expected(&self, instance: &mut RawInstance) -> Vec<u8> {
        assert!(instance.gas() >= 0 && instance.program_counter().is_none());
        let mut out = b"PVMDOME1".to_vec();
        out.extend((instance.gas() as u64).to_le_bytes());
        for index in 0..13 {
            out.extend(instance.reg(Reg::from_raw(index).unwrap()).to_le_bytes());
        }
        for &(address, _) in &self.pages {
            out.extend(instance.read_memory(address, 4096).unwrap());
        }
        out
    }
    // Apply only the five known imports; bounded output and ROM extents reject a runaway guest.
    #[inline(never)]
    fn run(&self, instance: &mut RawInstance, rom: &[u8]) -> Events {
        let mut events = Events {
            records: Vec::new(),
            length: 0,
        };
        for _ in 0..4096 {
            match instance.run().unwrap() {
                InterruptKind::Finished => return events,
                InterruptKind::Ecalli(id) => {
                    let kind = self.hosts.iter().position(|x| *x == id).unwrap();
                    let a = instance.reg(Reg::A0);
                    let b = instance.reg(Reg::A1);
                    let c = instance.reg(Reg::A2);
                    let address = u32::try_from(a).unwrap();
                    match kind {
                        2 => {
                            // A complete bounded immutable WAD range is copied through the public VM API.
                            let chunk = rom
                                .get(
                                    usize::try_from(b).unwrap()
                                        ..usize::try_from(b.checked_add(c).unwrap()).unwrap(),
                                )
                                .unwrap();
                            instance.write_memory(address, chunk).unwrap();
                        }
                        3 => instance.set_reg(Reg::A0, rom.len() as u64),
                        0 | 1 | 4 => {
                            // Byte-for-byte event framing is hashed by orchestration outside collection.
                            let length = match kind {
                                0 => b.checked_mul(4).unwrap(),
                                1 => {
                                    assert_eq!((b, c), (640, 400));
                                    b * c * 4
                                }
                                _ => b,
                            };
                            assert!(length <= 1048576);
                            let bytes = instance
                                .read_memory(address, u32::try_from(length).unwrap())
                                .unwrap();
                            if self.capture_events {
                                // Warmup transitions can emit many frames in one tick; only measured calls retain events.
                                events.length = events.length.checked_add(5 + bytes.len()).unwrap();
                                assert!(events.length <= 4 * 1024 * 1024);
                                events.records.push(OutputEvent {
                                    kind: kind as u8,
                                    bytes,
                                });
                            }
                            if kind == 4 {
                                instance.set_reg(Reg::A0, b);
                            }
                        }
                        _ => unreachable!(),
                    }
                }
                other => panic!("DOOM failed: {other:?} at {:?}", instance.program_counter()),
            }
        }
        panic!("DOOM host budget exhausted");
    }
}

// Prepare once; measured/profiled execution reads those immutable input and expected records.
// One canonical adapter encloses cold admission or resident reset through owned host outputs.
fn full_run(
    raw: Vec<u8>,
    rom: Vec<u8>,
    input: Vec<u8>,
    expected: Vec<u8>,
    expected_events: Vec<u8>,
    phase: usize,
    phase_name: &str,
) {
    let owner = measurement::OwnerWindow::start();
    {
        let mut cold_cpu = Some(measurement::CpuTimer::start_process());
        let mut cold_wall = Some(std::time::Instant::now());
        let mut guest = Guest::from_bytes(raw);
        assert!(input.len() >= 152 && &input[..8] == b"PVMDOM01");
        let wire_len = usize::try_from(word(&input, 8, 4)).unwrap();
        let page_count = usize::try_from(word(&input, 16, 4)).unwrap();
        assert!(wire_len <= 4 * 1024 * 1024 && page_count > 0 && page_count <= 8192);
        assert_eq!(input.len(), 152 + wire_len + page_count * 4101);
        assert_eq!(word(&input, 12, 4), u64::from(guest.entries[phase].0));
        let registers: [u64; 13] = std::array::from_fn(|index| word(&input, 48 + index * 8, 8));
        let gas = i64::try_from(word(&input, 40, 8)).unwrap();
        let label = format!("doom-{phase_name}");
        let mut retained = measurement::RetainedInterpreter::new(&guest.module, &label, 13);
        for sample in 0..13 {
            let cpu = if sample == 0 {
                cold_cpu.take().unwrap()
            } else {
                measurement::CpuTimer::start_process()
            };
            let wall = if sample == 0 {
                cold_wall.take().unwrap()
            } else {
                std::time::Instant::now()
            };
            let instance = retained.restore(sample, |instance| {
                for (index, value) in registers.iter().enumerate() {
                    instance.set_reg(Reg::from_raw(index as u32).unwrap(), *value);
                }
                instance.set_next_program_counter(guest.entries[phase]);
                instance.set_gas(gas);
                // Deliver the declared RW input directly; module-map enumeration is an external oracle.
                for record in input[152 + wire_len..].chunks_exact(4101) {
                    let address = u32::try_from(word(record, 0, 4))
                        .unwrap()
                        .checked_mul(4096)
                        .unwrap();
                    let access = record[4];
                    assert!(access == 1 || access == 2);
                    if access == 2 {
                        instance.write_memory(address, &record[5..]).unwrap();
                    }
                }
            });
            let events = guest.run(instance, &rom);
            let output_gas = instance.gas();
            // Event payloads already belong to events. Final RAM is a public borrow until the next reset.
            let wall_ns = wall.elapsed().as_nanos();
            let cpu = cpu.finish();
            assert!(output_gas >= 0);
            if sample == 0 {
                guest.prepare_oracles();
                assert_eq!(page_count, guest.pages.len());
                assert_eq!(wire_len, guest.wire.len());
                // Independent code/import/RO compatibility oracles stay outside the primary clock.
                assert_eq!(guest.wire, input[152..152 + wire_len]);
                for (index, id) in guest.hosts.iter().enumerate() {
                    assert_eq!(u64::from(*id), word(&input, 20 + index * 4, 4));
                }
                let mut cursor = 152 + wire_len;
                for &(address, access) in &guest.pages {
                    assert_eq!(word(&input, cursor, 4), u64::from(address / 4096));
                    assert_eq!(input[cursor + 4], access);
                    if access == 1 {
                        assert!(
                            instance.read_memory(address, 4096).unwrap()
                                == input[cursor + 5..cursor + 4101]
                        );
                    }
                    cursor += 4101;
                }
            }
            assert!(
                guest.expected(instance) == expected,
                "DOOM terminal state mismatch"
            );
            assert!(events.encode() == expected_events, "DOOM event mismatch");
            cpu.report_full_timing_failure(&label, sample, wall_ns);
            retained.complete_sample(sample);
            cpu.receipt(&label, sample);
            println!(
                "DOOM_SAMPLE,reference,{phase_name},{sample},{},{wall_ns}",
                cpu.total
            );
        }
        retained.finish();
    }
    owner.finish("doom-process");
    println!("DOOM_OK,reference,{phase_name},{}", expected_events.len());
}

fn main() {
    if measurement::clock_control() {
        return;
    }
    let args: Vec<String> = std::env::args().collect();
    assert!(args.len() >= 2);
    if args[1] == "link" {
        // Public pinned linking changes only the stack extent required by the original 16KiB example.
        assert_eq!(args.len(), 4);
        let mut config = polkavm_linker::Config::default();
        config.set_min_stack_size(16384);
        let bytes = polkavm_linker::program_from_elf(
            config,
            InstructionSetKind::JamV1.into(),
            &fs::read(&args[2]).unwrap(),
        )
        .unwrap();
        fs::write(&args[3], bytes).unwrap();
        return;
    }
    assert_eq!(args.len(), 6);
    assert!(args[1] == "prepare" || args[1] == "run");
    if std::env::var("RAGNAROK_PVM_DOOM_ASSERT").as_deref() == Ok("1") {
        panic!("doom reference assertion control");
    }
    measurement::invocation_scope_header();
    if measurement::full_invocation() && args[1] == "run" {
        // Fixture files are read before the real request boundary; there is no untimed code owner.
        let folder = Path::new(&args[4]);
        let phase = match args[5].as_str() {
            "init" => 0,
            "tick" => 1,
            _ => panic!("unknown DOOM phase"),
        };
        let raw = fs::read(&args[2]).unwrap();
        let rom = fs::read(&args[3]).unwrap();
        assert_eq!(rom.len(), 4196020);
        let input = fs::read(folder.join(format!("{}.input", args[5]))).unwrap();
        let expected = fs::read(folder.join(format!("{}.expected", args[5]))).unwrap();
        let events = fs::read(folder.join(format!("{}.events", args[5]))).unwrap();
        full_run(raw, rom, input, expected, events, phase, &args[5]);
        return;
    }
    let mut guest = Guest::load(Path::new(&args[2]));
    let rom = fs::read(&args[3]).unwrap();
    assert_eq!(rom.len(), 4196020);
    let folder = Path::new(&args[4]);
    if args[1] == "prepare" {
        // Warmup selects a bounded guest state; no warmup output is retained or profiled.
        let warmup: u32 = args[5].parse().unwrap();
        assert!(warmup <= 1320);
        fs::create_dir_all(folder).unwrap();
        let mut instance = guest.module.instantiate().unwrap();
        guest.reset(&mut instance, 0);
        fs::write(folder.join("init.input"), guest.input(&mut instance, 0)).unwrap();
        let events = guest.run(&mut instance, &rom);
        fs::write(folder.join("init.expected"), guest.expected(&mut instance)).unwrap();
        fs::write(folder.join("init.events"), events.encode()).unwrap();
        guest.capture_events = false;
        for _ in 0..warmup {
            guest.reset(&mut instance, 1);
            guest.run(&mut instance, &rom);
        }
        guest.capture_events = true;
        guest.reset(&mut instance, 1);
        fs::write(folder.join("tick.input"), guest.input(&mut instance, 1)).unwrap();
        let events = guest.run(&mut instance, &rom);
        fs::write(folder.join("tick.expected"), guest.expected(&mut instance)).unwrap();
        fs::write(folder.join("tick.events"), events.encode()).unwrap();
        println!(
            "DOOM_PREPARED,{warmup},{},{}",
            guest.pages.len(),
            guest.wire.len()
        );
        return;
    }
    let phase = match args[5].as_str() {
        "init" => 0,
        "tick" => 1,
        _ => panic!("unknown DOOM phase"),
    };
    let input = fs::read(folder.join(format!("{}.input", args[5]))).unwrap();
    assert!(input.len() >= 152 && &input[..8] == b"PVMDOM01");
    let requested = std::env::var("RAGNAROK_PVM_DOOM_TIMING").unwrap_or_default();
    assert!(matches!(requested.as_str(), "" | "0" | "1"));
    let timing = requested == "1";
    let lifecycle_requested = std::env::var("RAGNAROK_PVM_DOOM_LIFECYCLE").unwrap_or_default();
    assert!(matches!(lifecycle_requested.as_str(), "" | "0" | "1"));
    let canonical = measurement::retained_protocol();
    // Historical lifecycle consumers measure fresh-instance teardown; canonical metadata has one final drop.
    let lifecycle = timing && lifecycle_requested == "1" && !canonical;
    let samples = if timing { 13 } else { 1 };
    let expected_events = fs::read(folder.join(format!("{}.events", args[5]))).unwrap();
    let label = format!("doom-{}", args[5]);
    let mut retained =
        canonical.then(|| measurement::RetainedInterpreter::new(&guest.module, &label, samples));
    for sample in 0..samples {
        // Keep call-only timing unchanged; optionally account for private instance construction and restoration separately.
        let restore_start = if lifecycle {
            measurement::process_cpu()
        } else {
            0
        };
        let mut legacy_instance = if canonical {
            None
        } else {
            Some(guest.module.instantiate().unwrap())
        };
        let restore = |instance: &mut RawInstance| {
            guest.reset(instance, phase);
            let mut cursor = 152 + guest.wire.len();
            assert_eq!(word(&input, 8, 4) as usize, guest.wire.len());
            assert_eq!(input.len(), cursor + guest.pages.len() * 4101);
            for &(address, access) in &guest.pages {
                // Read-only bytes are checked against the module; only writable pages may be restored.
                assert_eq!(word(&input, cursor, 4), u64::from(address / 4096));
                assert_eq!(input[cursor + 4], access);
                let bytes = &input[cursor + 5..cursor + 4101];
                if access == 2 {
                    instance.write_memory(address, bytes).unwrap();
                } else {
                    assert_eq!(instance.read_memory(address, 4096).unwrap(), bytes);
                }
                cursor += 4101;
            }
        };
        let instance = if let Some(retained) = retained.as_mut() {
            retained.restore(sample, restore)
        } else {
            let instance = legacy_instance.as_mut().unwrap();
            restore(instance);
            instance
        };
        // Complete independent input-state validation stays outside both execution and restoration accounting.
        let restore_elapsed = if lifecycle {
            measurement::process_cpu() - restore_start
        } else {
            0
        };
        assert!(
            guest.input(instance, phase) == input,
            "DOOM initial state mismatch"
        );
        let cpu = timing.then(|| measurement::CpuTimer::start(instance));
        let wall = timing.then(std::time::Instant::now);
        let events = guest.run(instance, &rom);
        let wall_elapsed = wall.map(|value| value.elapsed().as_nanos()).unwrap_or(0);
        let cpu = cpu.map(|clock| clock.finish());
        let cpu_elapsed = cpu.as_ref().map_or(0, |value| value.total);
        assert!(
            guest.expected(instance)
                == fs::read(folder.join(format!("{}.expected", args[5]))).unwrap(),
            "DOOM terminal state mismatch"
        );
        assert!(
            events.encode() == fs::read(folder.join(format!("{}.events", args[5]))).unwrap(),
            "DOOM event mismatch"
        );
        if let Some(retained) = retained.as_mut() {
            // Both full golden oracles precede any accepted cache/restore receipt.
            if timing {
                assert!(cpu_elapsed > 0 && wall_elapsed > 0);
            }
            retained.complete_sample(sample);
        }
        let teardown_elapsed = if lifecycle {
            // Dispose the exclusive instance after validation; keep teardown outside call-only timing but inside lifecycle accounting.
            let teardown_start = measurement::process_cpu();
            drop(legacy_instance.take().unwrap());
            measurement::process_cpu() - teardown_start
        } else {
            // Ordinary call-only runs retain their original automatic end-of-iteration cleanup.
            0
        };
        if timing {
            // Validation precedes publication of every measured CPU/wall duration.
            assert!(cpu_elapsed > 0 && wall_elapsed > 0);
            cpu.as_ref()
                .unwrap()
                .receipt(&format!("doom-{}", args[5]), sample);
            println!(
                "DOOM_SAMPLE,reference,{},{sample},{cpu_elapsed},{wall_elapsed}",
                args[5]
            );
            if lifecycle {
                // Publish paired phases only after complete final-state and ordered-event checks pass.
                assert!(restore_elapsed > 0);
                println!(
                    "DOOM_LIFECYCLE,reference,{},{sample},{restore_elapsed},{cpu_elapsed},{teardown_elapsed},{}",
                    args[5],
                    restore_elapsed + cpu_elapsed + teardown_elapsed
                );
            }
        }
    }
    if let Some(retained) = retained {
        // The retained case has exactly one teardown after its complete sample cohort.
        retained.finish();
    }
    println!("DOOM_OK,reference,{},{}", args[5], expected_events.len());
}
