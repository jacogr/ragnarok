// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Compare independent scalar memory witnesses through pinned public JamV1 interpreter APIs.
// @@PvmReference={"input":"pvm-memory-access.bin","suite":"pvm_memory_access_reference"}
use polkavm::{
    BackendKind, Config, Engine, InterruptKind, MemoryProtection, Module, ModuleConfig,
    ProgramBlob, ProgramCounter, ProgramParts, Reg,
};
use polkavm_common::program::InstructionSetKind;

// Fixed fields are read only after the caller has checked the complete record header.
fn word(data: &[u8], at: usize, width: usize) -> u64 {
    let mut value = 0_u64;
    for i in 0..width {
        value |= u64::from(data[at + i]) << (8 * i);
    }
    value
}

fn main() {
    let path = std::env::args().nth(1).expect("provide PVMMAC01 corpus");
    let data = std::fs::read(path).unwrap();
    assert!(data.len() >= 12 && &data[..8] == b"PVMMAC01");
    let count = word(&data, 8, 4) as usize;
    assert!((1..=20000).contains(&count));
    let mut config = Config::default();
    config.set_backend(Some(BackendKind::Interpreter));
    config.set_allow_dynamic_paging(true);
    let engine = Engine::new(&config).unwrap();
    let mut profile = ModuleConfig::new();
    profile.set_page_size(4096);
    profile.set_dynamic_paging(true);
    let mut cursor = 12;
    let mut compatibility_cases = 0;
    for row in 0..count {
        // Every fixed field and blob extent is checked before slicing or narrowing.
        assert!(data.len() - cursor >= 234, "row {row}: header");
        let header = &data[cursor..cursor + 234];
        let length = word(header, 0, 4) as usize;
        let exit = header[4];
        let fault = word(header, 5, 4) as u32;
        let address = word(header, 9, 4) as usize;
        let width = header[13] as usize;
        let seed = header[16] as usize;
        let writes = header[17] as usize;
        assert!(matches!(exit, 0 | 2) && matches!(width, 1 | 2 | 4 | 8));
        assert!(address >= 0x10000 && address + width <= 0x12000);
        assert!(writes == 0 || writes == width);
        cursor += 234;
        assert!(length <= 32 && length <= data.len() - cursor);
        let wire = &data[cursor..cursor + length];
        assert!(wire.len() >= 4);
        let trap_pc = u32::from(wire[2]) - 1;
        cursor += length;
        // Preserve the GP expectation; only GP-PVM-008 changes the compatibility fault address.
        let storing = matches!(wire[3], 30..=33 | 59..=62 | 70..=73 | 120..=123);
        let expected_fault = if storing
            && address < 0x11000
            && address + width > 0x11000
            && header[14] == 2
            && header[15] == 0
        {
            assert_eq!(fault, 0x10000);
            compatibility_cases += 1;
            0x11000
        } else {
            fault
        };
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = wire.to_vec().into();
        let blob = ProgramBlob::from_parts(parts).unwrap();
        let module = Module::from_blob(&engine, &profile, blob).unwrap();
        let mut instance = module.instantiate().unwrap();
        for page in 0..2 {
            // Allocate only present pages and seed unequal bytes before applying read-only protection.
            let mapping = header[14 + page];
            assert!(mapping <= 2);
            if mapping != 0 {
                let start = 0x10000 + page as u32 * 4096;
                instance
                    .zero_memory_with_memory_protection(start, 4096, MemoryProtection::ReadWrite)
                    .unwrap();
                let bytes: Vec<u8> = (0..4096)
                    .map(|i| {
                        let index = page * 4096 + i;
                        ((index * 37 + seed) ^ (index >> 4)) as u8
                    })
                    .collect();
                instance.write_memory(start, &bytes).unwrap();
                if mapping == 2 {
                    instance.protect_memory(start, 4096).unwrap();
                }
            }
        }
        for index in 0..13 {
            instance.set_reg(
                Reg::from_raw(index as u32).unwrap(),
                word(header, 26 + index * 8, 8),
            );
        }
        instance.set_next_program_counter(ProgramCounter(0));
        match instance.run().unwrap() {
            InterruptKind::Trap => {
                assert_eq!(exit, 0, "row {row}");
                assert_eq!(
                    instance.program_counter(),
                    Some(ProgramCounter(trap_pc)),
                    "row {row}"
                );
            }
            InterruptKind::Segfault(actual) => {
                assert_eq!(exit, 2, "row {row}");
                assert_eq!(actual.page_address, expected_fault, "row {row}");
                let fault_mapping = header[14 + (expected_fault as usize - 0x10000) / 4096];
                assert_eq!(
                    actual.is_write_protected,
                    storing && fault_mapping == 2,
                    "row {row}"
                );
                assert_eq!(
                    instance.program_counter(),
                    Some(ProgramCounter(0)),
                    "row {row}"
                );
            }
            other => panic!("row {row}: unexpected {other:?}"),
        }
        for index in 0..13 {
            assert_eq!(
                instance.reg(Reg::from_raw(index as u32).unwrap()),
                word(header, 130 + index * 8, 8),
                "row {row}: register {index}"
            );
        }
        for page in 0..2 {
            // Check every mapped byte, including untouched store prefixes after a cross-page failure.
            if header[14 + page] != 0 {
                let observed = instance
                    .read_memory(0x10000 + page as u32 * 4096, 4096)
                    .unwrap();
                for (i, actual) in observed.iter().enumerate() {
                    let index = page * 4096 + i;
                    let absolute = 0x10000 + index;
                    let expected = if absolute >= address && absolute - address < writes {
                        header[18 + absolute - address]
                    } else {
                        ((index * 37 + seed) ^ (index >> 4)) as u8
                    };
                    assert_eq!(*actual, expected, "row {row}: byte {absolute:#x}");
                }
            }
        }
    }
    assert_eq!(cursor, data.len());
    assert_eq!(compatibility_cases, 48);
    println!("PolkaVM scalar memory cross-check passed: {count} rows");
}
