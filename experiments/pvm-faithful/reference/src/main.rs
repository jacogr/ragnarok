// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Independent reference witnesses using unchanged pinned PolkaVM's public APIs.
//! Corpus publication happens after all cases succeed; candidate code is never consulted.

mod decode;
mod decode_match;
mod execution;
mod host;
mod iterator;
mod layout;
mod operations;
mod program;
mod simulator;

use polkavm::{
    BackendKind, Config, Engine, InterruptKind, Module, ModuleConfig, ProgramBlob, ProgramCounter,
    Reg,
};
use polkavm_common::program::{asm, Instruction, InstructionSetKind};
use polkavm_common::writer::ProgramBlobBuilder;

fn module(engine: &Engine, instruction: Instruction) -> Module {
    // Fixed module geometry deliberately includes non-resident zero and initial-data tails.
    let mut builder = ProgramBlobBuilder::new(InstructionSetKind::JamV1);
    builder.set_ro_data_size(4096);
    builder.set_rw_data_size(8192);
    builder.set_stack_size(65536);
    builder.set_ro_data(vec![1, 2, 3, 4]);
    builder.set_rw_data(vec![5, 6, 7, 8]);
    builder.set_code(&[instruction, asm::ret()], &[]);
    let blob = ProgramBlob::parse(builder.into_vec().unwrap().into()).unwrap();
    let mut config = ModuleConfig::new();
    config.set_page_size(4096);
    config.set_aux_data_size(4096);
    Module::from_blob(engine, &config, blob).unwrap()
}

fn operation(store: bool, width: u8, address: u32) -> Instruction {
    // Direct-address scalar operations isolate memory behavior from candidate instruction decoding.
    match (store, width) {
        (false, 1) => asm::load_u8(Reg::A0, address as i32),
        (false, 2) => asm::load_u16(Reg::A0, address as i32),
        (false, 4) => asm::load_u32(Reg::A0, address as i32),
        (false, 8) => asm::load_u64(Reg::A0, address as i32),
        (true, 1) => asm::store_u8(Reg::A0, address as i32),
        (true, 2) => asm::store_u16(Reg::A0, address as i32),
        (true, 4) => asm::store_u32(Reg::A0, address as i32),
        (true, 8) => asm::store_u64(Reg::A0, address as i32),
        _ => panic!("foreign witness operation"),
    }
}

fn standard_memory(path: &str) {
    // Force the upstream interpreter; another available backend cannot stand in for this oracle.
    let mut config = Config::default();
    config.set_backend(Some(BackendKind::Interpreter));
    let engine = Engine::new(&config).unwrap();
    let template = module(&engine, asm::trap());
    let map = template.memory_map();
    let geometry = [
        map.page_size(),
        map.ro_data_address(),
        map.rw_data_address(),
        map.stack_address_low(),
        map.stack_address_high(),
        map.aux_data_address(),
        map.ro_data_size(),
        map.rw_data_size(),
        map.stack_size(),
        map.aux_data_size(),
        map.heap_base(),
        map.max_heap_size(),
    ];
    let regions = [
        (geometry[1], geometry[6]),
        (geometry[2], geometry[7]),
        (geometry[3], geometry[8]),
        (geometry[5], geometry[9]),
    ];
    let mut addresses = vec![0, 0xffff, u32::MAX];
    for &(base, length) in &regions {
        // Cover before/start/unaligned/interior/end spans in every virtual region.
        for delta in [0, 1, 3, length - 8, length - 1, length] {
            addresses.push(base + delta);
        }
        addresses.push(base - 1);
    }
    addresses.sort_unstable();
    addresses.dedup();
    let count = (addresses.len() * 4 * 2 * 3) as u32;
    let mut output = b"PVFSMM01".to_vec();
    for value in geometry {
        output.extend_from_slice(&value.to_le_bytes());
    }
    output.extend_from_slice(&count.to_le_bytes());
    for phase in 0..3_u8 {
        for &address in &addresses {
            for width in [1, 2, 4, 8] {
                for store in [false, true] {
                    let module = module(&engine, operation(store, width, address));
                    let mut instance = module.instantiate().unwrap();
                    if phase != 0 {
                        // Populate each writable region; phase two then verifies retained-allocation reset.
                        for &(base, length) in &regions[1..] {
                            instance
                                .write_memory(base, &vec![0xa5; length as usize])
                                .unwrap();
                        }
                        if phase == 2 {
                            instance.reset_memory().unwrap();
                        }
                    }
                    instance.set_reg(Reg::RA, polkavm::RETURN_TO_HOST);
                    instance.set_reg(Reg::A0, 0x8877665544332211);
                    instance.set_next_program_counter(ProgramCounter(0));
                    let exit = match instance.run().unwrap() {
                        InterruptKind::Finished => 0_u8,
                        InterruptKind::Trap => 1,
                        other => panic!("unexpected standard memory interrupt: {other:?}"),
                    };
                    output.extend_from_slice(&[phase, u8::from(store), width]);
                    output.extend_from_slice(&address.to_le_bytes());
                    output.push(exit);
                    output.extend_from_slice(&instance.reg(Reg::A0).to_le_bytes());
                    for &(base, length) in &regions {
                        // Retain every mapped byte, including untouched prefixes, suffixes and padding.
                        output.extend_from_slice(&instance.read_memory(base, length).unwrap());
                    }
                }
            }
        }
    }
    std::fs::write(path, output).unwrap();
    println!("faithful upstream standard-memory witnesses: {count}");
}

fn main() {
    // Missing/foreign commands are failures, never an empty accepted corpus.
    let args: Vec<_> = std::env::args().collect();
    assert_eq!(args.len(), 3);
    match args[1].as_str() {
        "standard-memory" => standard_memory(&args[2]),
        "decode" => decode::generate(&args[2]),
        "iterator" => iterator::generate(&args[2]),
        "operations" => operations::generate(&args[2]),
        "program" => program::generate(&args[2]),
        "layout" => layout::generate(&args[2]),
        "simulator" => simulator::generate(&args[2]),
        "execution" => execution::generate(&args[2]),
        "host" => host::generate(&args[2]),
        other => panic!("unknown reference command: {other}"),
    }
}
