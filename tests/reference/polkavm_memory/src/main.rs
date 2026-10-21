// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Regenerate twelve final-byte fixtures using only pristine pinned PolkaVM public APIs.
//! Output is a portable little-endian test corpus; runtime builds consume frozen bytes, not Rust.

use polkavm::{
    BackendKind, Config, Engine, InterruptKind, MemoryProtection, Module, ModuleConfig,
    ProgramBlob, Reg,
};
use polkavm_common::program::{asm, InstructionSetKind};
use polkavm_common::writer::ProgramBlobBuilder;

fn main() {
    // The caller selects an ignored output path; regeneration never advances upstream pins.
    let path = std::env::args()
        .nth(1)
        .expect("provide a fixture output path");
    let mut config = Config::default();
    config.set_backend(Some(BackendKind::Interpreter));
    config.set_allow_dynamic_paging(true);
    let engine = Engine::new(&config).unwrap();
    let mut data = b"PVMMEM01".to_vec();
    data.extend_from_slice(&12_u32.to_le_bytes());
    for address in [0xfffffffe_u32, 0xffffffff] {
        // Zero means absent, one read-write, two read-only. Allocate before protection.
        for mapping in 0_u8..3 {
            for store in [false, true] {
                // A single byte operation and return isolate memory from pipeline/gas models.
                let mut builder = ProgramBlobBuilder::new(InstructionSetKind::JamV1);
                builder.add_export_by_basic_block(0, b"main");
                let op = if store {
                    asm::store_u8(Reg::A0, address as i32)
                } else {
                    asm::load_u8(Reg::A0, address as i32)
                };
                builder.set_code(&[op, asm::ret()], &[]);
                let blob = ProgramBlob::parse(builder.into_vec().unwrap().into()).unwrap();
                let mut module_config = ModuleConfig::new();
                module_config.set_page_size(4096);
                module_config.set_dynamic_paging(true);
                let module = Module::from_blob(&engine, &module_config, blob).unwrap();
                let mut instance = module.instantiate().unwrap();
                instance.set_reg(Reg::RA, polkavm::RETURN_TO_HOST);
                instance.set_reg(Reg::A0, 99);
                if mapping != 0 {
                    // Plain zero_memory requires an existing mapping; this API allocates pages.
                    instance
                        .zero_memory_with_memory_protection(
                            0xfffff000,
                            4096,
                            MemoryProtection::ReadWrite,
                        )
                        .unwrap();
                    instance.write_memory(0xfffff000, &[7; 4096]).unwrap();
                    if mapping == 2 {
                        // Protection is applied after seeding sentinel bytes through the host API.
                        instance.protect_memory(0xfffff000, 4096).unwrap();
                    }
                }
                instance.set_next_program_counter(polkavm::ProgramCounter(0));
                let interrupt = instance.run().unwrap();
                let (exit, fault) = match interrupt {
                    InterruptKind::Finished => (0_u8, 0),
                    InterruptKind::Trap => (1, 0),
                    InterruptKind::Segfault(fault) => (2, fault.page_address),
                    // An unexpected exit must prevent publishing a misleading partial corpus.
                    other => panic!("unexpected interrupt: {other:?}"),
                };
                data.extend_from_slice(&u64::from(address).to_le_bytes());
                data.push(mapping);
                data.push(if store { 59 } else { 52 });
                data.push(exit);
                data.extend_from_slice(&fault.to_le_bytes());
                data.extend_from_slice(&instance.reg(Reg::A0).to_le_bytes());
                if mapping == 0 {
                    // Absent-page records have no page image; these bytes are format placeholders.
                    data.extend_from_slice(&[0, 0]);
                } else {
                    data.push(instance.read_u8(0xfffffffe).unwrap());
                    data.push(instance.read_u8(0xffffffff).unwrap());
                }
            }
        }
    }
    // Write only after the full reference run completes successfully.
    assert_eq!(data.len(), 12 + 12 * 25);
    std::fs::write(path, data).unwrap();
    println!("PolkaVM JamV1 dynamic-memory fixtures: 12");
}
