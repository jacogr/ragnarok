// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Regenerate scalar boundary fixtures using only pristine pinned PolkaVM public APIs.
//! Output is a portable little-endian test corpus; runtime builds consume frozen bytes, not Rust.

// @@PvmReference={"regenerate":"pvm-memory-boundary.bin","suite":"pvm_memory_boundary_reference"}
use polkavm::{InterruptKind, MemoryProtection, Module, ModuleConfig, ProgramBlob, Reg};
use polkavm_common::program::{asm, InstructionSetKind};
use polkavm_common::writer::ProgramBlobBuilder;

fn main() {
    // Capability inspection is read-only and never writes the requested fixture output.
    if std::env::args().nth(1).as_deref() == Some("--backend-info") {
        ragnarok_memory_probe::backend_info();
        return;
    }
    // The caller selects an ignored output path; regeneration never advances upstream pins.
    let path = std::env::args()
        .nth(1)
        .expect("provide a fixture output path");
    let engine = ragnarok_memory_probe::engine(true);
    let mut cases = Vec::new();
    // Retain the original twelve records first, in their original byte order.
    for address in [0xfffffffe_u32, 0xffffffff] {
        for mapping in 0_u8..3 {
            for opcode in [52_u8, 59] {
                cases.push((address, mapping, opcode));
            }
        }
    }
    for opcode in [53_u8, 54, 55, 56, 57, 58, 60, 61, 62] {
        let width = match opcode {
            53 => 1,
            54 | 55 | 60 => 2,
            56 | 57 | 61 => 4,
            58 | 62 => 8,
            _ => unreachable!(),
        };
        let mut addresses = vec![u32::MAX - width, u32::MAX - width + 1];
        if width > 1 {
            addresses.push(u32::MAX);
        }
        for address in addresses {
            for mapping in 0_u8..3 {
                cases.push((address, mapping, opcode));
            }
        }
    }
    assert_eq!(cases.len(), 90);
    let mut data = b"PVMMEM01".to_vec();
    data.extend_from_slice(&(cases.len() as u32).to_le_bytes());
    for (address, mapping, opcode) in cases {
        let mut builder = ProgramBlobBuilder::new(InstructionSetKind::JamV1);
        builder.add_export_by_basic_block(0, b"main");
        let op = match opcode {
            52 => asm::load_u8(Reg::A0, address as i32),
            53 => asm::load_i8(Reg::A0, address as i32),
            54 => asm::load_u16(Reg::A0, address as i32),
            55 => asm::load_i16(Reg::A0, address as i32),
            56 => asm::load_u32(Reg::A0, address as i32),
            57 => asm::load_i32(Reg::A0, address as i32),
            58 => asm::load_u64(Reg::A0, address as i32),
            59 => asm::store_u8(Reg::A0, address as i32),
            60 => asm::store_u16(Reg::A0, address as i32),
            61 => asm::store_u32(Reg::A0, address as i32),
            62 => asm::store_u64(Reg::A0, address as i32),
            _ => unreachable!(),
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
                .zero_memory_with_memory_protection(0xfffff000, 4096, MemoryProtection::ReadWrite)
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
        data.push(opcode);
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
    // Write only after the full reference run completes successfully.
    assert_eq!(data.len(), 12 + 90 * 25);
    std::fs::write(path, data).unwrap();
    println!("PolkaVM JamV1 dynamic-memory fixtures: 90");
}
