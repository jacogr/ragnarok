// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Public interpreted host memory replacement, permission withdrawal and metered multi-stage repair.
// @@PvmReference={"input":"pvm-mixed-program.bin","suite":"pvm_host_memory_reentry_reference"}
use polkavm::{
    CacheModel, CostModelKind, GasMeteringKind, InterruptKind, MemoryProtection, Module,
    ModuleConfig, ProgramBlob, ProgramCounter, ProgramParts, RawInstance, Reg,
};
use polkavm_common::program::InstructionSetKind;

// Track exact public page permissions independently of the interpreter instance.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Access {
    Missing,
    ReadOnly,
    ReadWrite,
}

// Fixed fields are read only after proving the enclosing 268-byte record exists.
fn word(data: &[u8], at: usize, width: usize) -> u64 {
    let mut value = 0;
    for i in 0..width {
        value |= u64::from(data[at + i]) << (8 * i);
    }
    value
}

// Original byte equations keep all neighboring bytes independent of the interpreter's scalar operations.
fn image(address: u32, scalar: u64, marks: [u8; 2]) -> Vec<u8> {
    let mut bytes = vec![33; 8192];
    bytes[32] = marks[0];
    bytes[4096 + 32] = marks[1];
    let at = (address - 0x10000) as usize;
    bytes[at..at + 8].copy_from_slice(&scalar.to_le_bytes());
    bytes
}

// The complete register file follows modular arithmetic, not observations copied from an execution.
fn registers(input: &[u64; 13], initial: u64, iteration: u64, incremented: bool) -> [u64; 13] {
    let mut values = *input;
    values[7] = initial
        .wrapping_add(iteration)
        .wrapping_add(u64::from(incremented));
    values[8] = initial
        .wrapping_mul(iteration)
        .wrapping_add(iteration * (iteration + 1) / 2);
    values[10] = iteration;
    values
}

// Every host/fault boundary must retain exact gas, PC and all original-register aliases.
fn check_cpu(instance: &RawInstance, values: &[u64; 13], pc: u32, gas: u64) {
    assert_eq!(instance.program_counter(), Some(ProgramCounter(pc)));
    assert_eq!(instance.gas(), gas as i64);
    for (i, value) in values.iter().enumerate() {
        assert_eq!(instance.reg(Reg::from_raw(i as u32).unwrap()), *value);
    }
}

// Missing public VM pages have no readable image; native retained inaccessible-image bytes are checked separately.
fn check_memory(
    instance: &mut RawInstance,
    address: u32,
    scalar: u64,
    marks: [u8; 2],
    access: [Access; 2],
) {
    let expected = image(address, scalar, marks);
    for (page, permission) in access.iter().enumerate() {
        let base = 0x10000 + page as u32 * 4096;
        assert_eq!(
            instance.is_memory_accessible(base, 4096, MemoryProtection::Read),
            *permission != Access::Missing
        );
        assert_eq!(
            instance.is_memory_accessible(base, 4096, MemoryProtection::ReadWrite),
            *permission == Access::ReadWrite
        );
        if *permission == Access::Missing {
            assert!(instance.read_memory(base, 4096).is_err());
        } else {
            // Compare entire pages without dumping thousands of bytes on a mismatch.
            assert!(
                instance.read_memory(base, 4096).unwrap()
                    == expected[page * 4096..(page + 1) * 4096]
            );
        }
    }
}

fn main() {
    let data = std::fs::read(std::env::args().nth(1).expect("provide PVMMIX01 corpus")).unwrap();
    assert!(data.len() >= 12 && &data[..8] == b"PVMMIX01");
    assert_eq!(word(&data, 8, 4), 32);
    let engine = ragnarok_memory_probe::engine(true);
    let mut profile = ModuleConfig::new();
    profile.set_page_size(4096);
    profile.set_dynamic_paging(true);
    profile.set_gas_metering(Some(GasMeteringKind::Sync));
    profile.set_cost_model(Some(CostModelKind::Full(CacheModel::L2Hit)));
    let mut cursor = 12;
    let mut callbacks = 0;
    let mut faults = 0;
    for _row in 0..32 {
        assert!(data.len() - cursor >= 268);
        let h = &data[cursor..cursor + 268];
        let length = word(h, 0, 4) as usize;
        let iterations = word(h, 4, 4);
        let address = word(h, 8, 4) as u32;
        let initial = word(h, 12, 8);
        let price = word(h, 28, 8);
        let halt_price = word(h, 44, 8);
        assert!(matches!(iterations, 1 | 2 | 7 | 31) && matches!(address, 0x10000 | 0x10fff));
        assert_eq!(
            (price, word(h, 36, 8), halt_price, word(h, 52, 8)),
            (103, 106, 22, 25)
        );
        let mut input = [0; 13];
        for (i, value) in input.iter_mut().enumerate() {
            *value = word(h, 60 + i * 8, 8);
        }
        let final_values = registers(&input, initial, iterations, false);
        for (i, value) in final_values.iter().enumerate() {
            assert_eq!(*value, word(h, 164 + i * 8, 8));
        }
        assert_eq!(word(h, 20, 8), initial.wrapping_add(iterations));
        cursor += 268;
        assert!(length >= 4 && length <= 64 && length <= data.len() - cursor);
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = data[cursor..cursor + length].to_vec().into();
        cursor += length;
        let module =
            Module::from_blob(&engine, &profile, ProgramBlob::from_parts(parts).unwrap()).unwrap();
        assert_eq!(
            module.calculate_gas_cost_for(ProgramCounter(0)),
            Some(price as i64)
        );
        assert_eq!(
            module.calculate_gas_cost_for(ProgramCounter(20)),
            Some(halt_price as i64)
        );
        let total = iterations * price + halt_price;
        for scenario in 0..4 {
            // Every gas scenario starts from a separate public instance and two writable pages.
            let budget = match scenario {
                0 => total + 7,
                1 => total,
                2 => total - 1,
                _ => price - 1,
            };
            let mut instance = module.instantiate().unwrap();
            instance
                .zero_memory_with_memory_protection(0x10000, 8192, MemoryProtection::ReadWrite)
                .unwrap();
            instance
                .write_memory(0x10000, &image(address, initial, [33, 33]))
                .unwrap();
            for (i, value) in input.iter().enumerate() {
                instance.set_reg(Reg::from_raw(i as u32).unwrap(), *value);
            }
            instance.set_gas(budget as i64);
            instance.set_next_program_counter(ProgramCounter(0));
            let mut calls = 0;
            let mut failed = 0;
            let mut interrupts = 0;
            let mut access = [Access::ReadWrite; 2];
            loop {
                interrupts += 1;
                assert!(
                    interrupts <= 4 * iterations + 1,
                    "unbounded host/fault sequence"
                );
                match instance.run().unwrap() {
                    InterruptKind::Ecalli(id) => {
                        assert!(calls < 2 * iterations);
                        let iteration = calls / 2;
                        let prior = initial.wrapping_add(iteration);
                        let gas = budget - (iteration + 1) * price;
                        if calls % 2 == 0 {
                            // Replace both complete images before withdrawing permission for the pending store.
                            assert_eq!(id, 13);
                            check_cpu(
                                &instance,
                                &registers(&input, initial, iteration, false),
                                3,
                                gas,
                            );
                            let previous = if iteration == 0 {
                                [33, 33]
                            } else {
                                [(116 + iteration) as u8, (176 + iteration) as u8]
                            };
                            check_memory(&mut instance, address, prior, previous, access);
                            instance.set_reg(Reg::A0, prior.wrapping_add(1));
                            let marks = [(17 + iteration) as u8, (77 + iteration) as u8];
                            instance
                                .write_memory(0x10000, &image(address, prior, marks))
                                .unwrap();
                            instance.protect_memory(0x10000, 4096).unwrap();
                            instance.free_pages(0x11000, 4096).unwrap();
                            access = [Access::ReadOnly, Access::Missing];
                            check_memory(&mut instance, address, prior, marks, access);
                        } else {
                            // The repaired guest store is visible before this host restores a completely writable image.
                            assert_eq!(id, 14);
                            check_cpu(
                                &instance,
                                &registers(&input, initial, iteration, true),
                                8,
                                gas,
                            );
                            let scalar = prior.wrapping_add(1);
                            check_memory(
                                &mut instance,
                                address,
                                scalar,
                                [(17 + iteration) as u8, (77 + iteration) as u8],
                                access,
                            );
                            instance.set_reg(Reg::A1, instance.reg(Reg::A1).wrapping_add(scalar));
                            if access[1] == Access::Missing {
                                instance
                                    .zero_memory_with_memory_protection(
                                        0x11000,
                                        4096,
                                        MemoryProtection::ReadWrite,
                                    )
                                    .unwrap();
                            }
                            let marks = [(117 + iteration) as u8, (177 + iteration) as u8];
                            instance
                                .write_memory(0x10000, &image(address, scalar, marks))
                                .unwrap();
                            access = [Access::ReadWrite; 2];
                            check_memory(&mut instance, address, scalar, marks, access);
                        }
                        calls += 1;
                    }
                    InterruptKind::Segfault(fault) => {
                        // Presence of the higher crossing page precedes the lower page's write permission.
                        assert!(scenario != 3 && calls % 2 == 1 && access[0] == Access::ReadOnly);
                        let iteration = calls / 2;
                        assert!(iteration < iterations);
                        let higher = address == 0x10fff && access[1] == Access::Missing;
                        assert_eq!(fault.page_address, if higher { 0x11000 } else { 0x10000 });
                        assert_eq!(fault.is_write_protected, !higher);
                        check_cpu(
                            &instance,
                            &registers(&input, initial, iteration, true),
                            5,
                            budget - (iteration + 1) * price,
                        );
                        let scalar = initial.wrapping_add(iteration);
                        let marks = [(17 + iteration) as u8, (77 + iteration) as u8];
                        check_memory(&mut instance, address, scalar, marks, access);
                        if higher {
                            instance
                                .zero_memory_with_memory_protection(
                                    0x11000,
                                    4096,
                                    MemoryProtection::ReadWrite,
                                )
                                .unwrap();
                            instance
                                .write_memory(0x11000, &image(address, scalar, marks)[4096..])
                                .unwrap();
                            access[1] = Access::ReadWrite;
                        } else {
                            instance.unprotect_memory(0x10000, 4096).unwrap();
                            access[0] = Access::ReadWrite;
                        }
                        check_memory(&mut instance, address, scalar, marks, access);
                        failed += 1;
                    }
                    InterruptKind::Finished => {
                        assert!(scenario < 2);
                        break;
                    }
                    InterruptKind::NotEnoughGas => {
                        assert!(scenario >= 2);
                        assert_eq!(
                            instance.program_counter(),
                            Some(ProgramCounter(if scenario == 2 { 20 } else { 0 }))
                        );
                        break;
                    }
                    other => panic!("unexpected interrupt {other:?}"),
                }
            }
            let progressed = scenario != 3;
            assert_eq!(calls, if progressed { 2 * iterations } else { 0 });
            assert_eq!(
                failed,
                if !progressed {
                    0
                } else if address == 0x10fff {
                    2 * iterations
                } else {
                    iterations
                }
            );
            assert_eq!(
                instance.gas(),
                (if scenario < 2 {
                    budget - total
                } else if scenario == 2 {
                    halt_price - 1
                } else {
                    budget
                }) as i64
            );
            for (i, value) in (if progressed { &final_values } else { &input })
                .iter()
                .enumerate()
            {
                assert_eq!(instance.reg(Reg::from_raw(i as u32).unwrap()), *value);
            }
            let scalar = if progressed {
                initial.wrapping_add(iterations)
            } else {
                initial
            };
            let marks = if progressed {
                [(116 + iterations) as u8, (176 + iterations) as u8]
            } else {
                [33, 33]
            };
            check_memory(
                &mut instance,
                address,
                scalar,
                marks,
                [Access::ReadWrite; 2],
            );
            callbacks += calls;
            faults += failed;
        }
    }
    assert_eq!(cursor, data.len());
    assert_eq!((callbacks, faults), (1968, 1476));
    println!("PolkaVM host memory reentry passed: 128 cases, 1968 callbacks, 1476 repaired faults");
}
