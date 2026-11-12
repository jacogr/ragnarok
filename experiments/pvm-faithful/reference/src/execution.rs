// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Full-instance oracle: raw opcode encodings, retained caches, host resumes and faults.
use polkavm::{
    BackendKind, CacheModel, Config, CostModelKind, Engine, GasMeteringKind, InterruptKind,
    MemoryProtection, Module, ModuleConfig, ProgramBlob, ProgramCounter, ProgramParts, Reg,
};
use polkavm_common::program::InstructionSetKind;

fn word(out: &mut Vec<u8>, value: u64, width: usize) {
    out.extend_from_slice(&value.to_le_bytes()[..width]);
}

pub fn generate(path: &str) {
    let mut config = Config::default();
    config.set_backend(Some(BackendKind::Interpreter));
    config.set_allow_dynamic_paging(true);
    let engine = Engine::new(&config).unwrap();
    let mut output = b"PVFEXE01".to_vec();
    word(&mut output, 4368, 4);
    let mut accepted = 0;
    let mut random = 0x9e3779b97f4a7c15_u64;
    for raw in 0..273_u16 {
        for sample in 0..8 {
            for dynamic in [false, true] {
                let length = [1, 2, 3, 4, 5, 8, 16, 25][sample];
                let mut code = vec![raw as u8; length];
                for byte in &mut code[1..] {
                    random ^= random << 13;
                    random ^= random >> 7;
                    random ^= random << 17;
                    *byte = if sample == 1 { 0 } else { random as u8 };
                }
                code.extend_from_slice(&[10, 3, 50, 0]);
                let mut mask = vec![0; code.len().div_ceil(8)];
                for pc in [0, length, length + 2] {
                    mask[pc / 8] |= 1 << (pc % 8);
                }
                if raw >= 256 && raw < 272 {
                    // Both branch targets are valid and each reaches a distinct observable host call.
                    let opcode = [
                        170, 171, 172, 173, 174, 175, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90,
                    ][(raw - 256) as usize];
                    let first = if raw < 262 { 3 } else { 4 };
                    code = if first == 3 {
                        vec![opcode, 0x87, 7]
                    } else {
                        vec![opcode, 0x17, if sample & 1 == 0 { 0 } else { 255 }, 8]
                    };
                    code.extend_from_slice(&[10, 13, 40, 5, 10, 14, 1, 50, 0]);
                    mask = vec![0; code.len().div_ceil(8)];
                    for pc in [0, first, first + 2, first + 4, first + 6, first + 7] {
                        mask[pc / 8] |= 1 << (pc % 8);
                    }
                } else if raw == 272 {
                    // External start at a host call, a following scalar instruction, and inside an operand.
                    code = vec![51, 7, 42, 10, 3, 51, 8, 9, 50, 0];
                    mask = vec![0x29, 1];
                }
                let mut wire = vec![3, 1, code.len() as u8, 0, length as u8, (length + 2) as u8];
                wire.extend_from_slice(&code);
                wire.extend_from_slice(&mask);
                word(&mut output, wire.len() as u64, 4);
                output.extend_from_slice(&wire);
                output.push(u8::from(dynamic));
                let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
                parts.code_and_jump_table = wire.into();
                parts.ro_data_size = 4096;
                parts.rw_data_size = 4096;
                parts.stack_size = 4096;
                parts.ro_data = vec![1, 2, 3, 4].into();
                parts.rw_data = vec![5, 6, 7, 8].into();
                let mut profile = ModuleConfig::new();
                profile.set_page_size(4096);
                profile.set_dynamic_paging(dynamic);
                profile.set_gas_metering(Some(GasMeteringKind::Sync));
                profile.set_cost_model(Some(CostModelKind::Full(CacheModel::L2Hit)));
                let blob = ProgramBlob::from_parts(parts).unwrap();
                let validation = blob.validate_code_with_isa(polkavm_common::program::ISA_JamV1);
                word(
                    &mut output,
                    validation.err().map_or(u32::MAX, |pc| pc.0) as u64,
                    4,
                );
                if validation.is_err() {
                    continue;
                }
                accepted += 1;
                let module = Module::from_blob(&engine, &profile, blob).unwrap();
                let map = module.memory_map();
                let addresses = if dynamic {
                    [0x10000, 0x10040, 0x10080]
                } else {
                    [
                        map.ro_data_address(),
                        map.rw_data_address(),
                        map.stack_address_high() - 64,
                    ]
                };
                for address in addresses {
                    word(&mut output, address as u64, 4);
                }
                let mut instance = module.instantiate().unwrap();
                for phase in 0..4 {
                    instance.reset_memory().unwrap();
                    if dynamic {
                        instance
                            .zero_memory_with_memory_protection(
                                0x10000,
                                4096,
                                MemoryProtection::ReadWrite,
                            )
                            .unwrap();
                        instance.write_memory(0x10000, &[1, 2, 3, 4]).unwrap();
                    }
                    for (index, reg) in Reg::ALL.iter().enumerate() {
                        let value = if index == 0 {
                            polkavm::RETURN_TO_HOST
                        } else {
                            [
                                0,
                                u64::MAX,
                                0x8000000000000000,
                                0x7fffffffffffffff,
                                1,
                                0x10000,
                                0x30000,
                                0xffffffffffff0000,
                            ][(index + sample + phase) % 8]
                        };
                        instance.set_reg(*reg, value);
                        word(&mut output, value, 8);
                    }
                    let initial_gas = [0, 512, 100, 2048][phase];
                    instance.set_gas(initial_gas);
                    let entry = if raw == 272 { [0, 3, 5, 6][phase] } else { 0 };
                    instance.set_next_program_counter(ProgramCounter(entry));
                    word(&mut output, initial_gas as u64, 8);
                    word(&mut output, entry as u64, 4);
                    let count_at = output.len();
                    output.push(0);
                    for step in 0..8 {
                        let exit = instance.run().unwrap();
                        let (kind, hostcall, page, size, protected) = match &exit {
                            InterruptKind::Finished => (0, 0, 0, 0, false),
                            InterruptKind::Trap => (1, 0, 0, 0, false),
                            InterruptKind::Ecalli(number) => (2, *number, 0, 0, false),
                            InterruptKind::NotEnoughGas => (3, 0, 0, 0, false),
                            InterruptKind::Segfault(fault) => (
                                4,
                                0,
                                fault.page_address,
                                fault.page_size,
                                fault.is_write_protected,
                            ),
                            other => panic!("unexpected oracle interrupt: {other:?}"),
                        };
                        output.push(kind);
                        for value in [hostcall, page, size] {
                            word(&mut output, value as u64, 4);
                        }
                        output.push(u8::from(protected));
                        for pc in [instance.program_counter(), instance.next_program_counter()] {
                            output.push(u8::from(pc.is_some()));
                            word(&mut output, pc.map_or(0, |pc| pc.0) as u64, 4);
                        }
                        word(&mut output, instance.gas() as u64, 8);
                        word(
                            &mut output,
                            instance.interpreter_cache_size().unwrap() as u64,
                            8,
                        );
                        for reg in Reg::ALL {
                            word(&mut output, instance.reg(reg), 8);
                        }
                        output[count_at] += 1;
                        match exit {
                            InterruptKind::Ecalli(_) => {
                                instance.set_reg(Reg::A5, (step + 17) as u64)
                            }
                            InterruptKind::NotEnoughGas if step == 0 => instance.set_gas(2048),
                            InterruptKind::Segfault(fault) if step < 3 => {
                                instance
                                    .zero_memory_with_memory_protection(
                                        fault.page_address,
                                        fault.page_size,
                                        MemoryProtection::ReadWrite,
                                    )
                                    .unwrap();
                            }
                            _ => break,
                        }
                    }
                    // Byte-for-byte windows supplement the separate full-region memory corpus.
                    for address in addresses {
                        let mut bytes = [0_u8; 64];
                        instance.read_memory_into(address, &mut bytes).unwrap();
                        output.extend_from_slice(&bytes);
                    }
                }
            }
        }
    }
    std::fs::write(path, output).unwrap();
    println!("faithful upstream execution witnesses: 4368 modules, {accepted} accepted, {} retained-instance invocations", accepted * 4);
}
