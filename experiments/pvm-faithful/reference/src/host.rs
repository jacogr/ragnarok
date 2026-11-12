// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Independent public host range, zeroing, mapping and protection behavior witnesses.
use polkavm::{
    BackendKind, Config, Engine, MemoryAccessError, MemoryProtection, Module, ModuleConfig,
    ProgramBlob, ProgramParts,
};
use polkavm_common::program::InstructionSetKind;

fn status(result: Result<(), MemoryAccessError>) -> u8 {
    match result {
        Ok(()) => 0,
        Err(MemoryAccessError::OutOfRangeAccess { .. }) => 1,
        Err(MemoryAccessError::MemoryLimitReached) => 2,
        Err(MemoryAccessError::Error(error)) => {
            let message = error.to_string();
            if message == "address not a multiple of page size" {
                4
            } else {
                assert!(message.contains("only possible on modules with dynamic paging"));
                3
            }
        }
    }
}

pub fn generate(path: &str) {
    let mut config = Config::default();
    config.set_backend(Some(BackendKind::Interpreter));
    config.set_allow_dynamic_paging(true);
    let engine = Engine::new(&config).unwrap();
    let addresses = [
        0,
        65535,
        65536,
        65537,
        69631,
        69632,
        73727,
        73728,
        73729,
        77824,
        196608,
        u32::MAX,
    ];
    let mut output = b"PVFHST01".to_vec();
    output.extend_from_slice(&840_u32.to_le_bytes());
    for dynamic in [false, true] {
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = vec![0, 0, 1, 0, 1].into();
        parts.ro_data_size = 4096;
        parts.rw_data_size = 4096;
        parts.stack_size = 4096;
        parts.ro_data = vec![1, 2, 3, 4].into();
        parts.rw_data = vec![5, 6, 7, 8].into();
        let mut profile = ModuleConfig::new();
        profile.set_dynamic_paging(dynamic);
        profile.set_page_size(4096);
        let module =
            Module::from_blob(&engine, &profile, ProgramBlob::from_parts(parts).unwrap()).unwrap();
        let map = module.memory_map();
        let snapshots = if dynamic {
            vec![65536, 69632, 73728, 77824, 81920]
        } else {
            vec![
                map.ro_data_address(),
                map.rw_data_address(),
                map.stack_address_low(),
            ]
        };
        let mut instance = module.instantiate().unwrap();
        for operation in 0..7 {
            for address in addresses {
                for length in [0_u32, 1, 2, 4096, 4097] {
                    instance.reset_memory().unwrap();
                    if dynamic {
                        for base in [65536, 69632, 77824] {
                            instance
                                .zero_memory_with_memory_protection(
                                    base,
                                    4096,
                                    MemoryProtection::ReadWrite,
                                )
                                .unwrap();
                            instance.write_memory(base, &vec![33; 4096]).unwrap();
                        }
                        instance.protect_memory(69632, 4096).unwrap();
                    }
                    output.extend_from_slice(&[u8::from(dynamic), operation]);
                    output.extend_from_slice(&address.to_le_bytes());
                    output.extend_from_slice(&length.to_le_bytes());
                    let mut buffer = vec![0xa5; length as usize];
                    let result = match operation {
                        0 => instance
                            .read_memory_into(address, buffer.as_mut_slice())
                            .map(|_| ()),
                        1 => instance.write_memory(address, &buffer),
                        2 => instance.zero_memory(address, length),
                        3 => instance.zero_memory_with_memory_protection(
                            address,
                            length,
                            MemoryProtection::ReadWrite,
                        ),
                        4 => instance.zero_memory_with_memory_protection(
                            address,
                            length,
                            MemoryProtection::Read,
                        ),
                        5 => instance.protect_memory(address, length),
                        6 => instance.unprotect_memory(address, length),
                        _ => unreachable!(),
                    };
                    output.push(status(result));
                    if operation == 0 {
                        output.extend_from_slice(&buffer);
                    }
                    output.push(snapshots.len() as u8);
                    for &base in &snapshots {
                        output.extend_from_slice(&base.to_le_bytes());
                        let mut bytes = [0_u8; 4096];
                        let readable = instance.read_memory_into(base, &mut bytes).is_ok();
                        output.push(u8::from(readable));
                        if readable {
                            output.extend_from_slice(&bytes);
                            output.push(u8::from(instance.write_memory(base, &bytes[..1]).is_ok()));
                        }
                    }
                }
            }
        }
    }
    std::fs::write(path, output).unwrap();
    println!("faithful upstream public host witnesses: 840 complete-memory cases");
}
