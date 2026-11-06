// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Cross-check independent GP conditional-control paths through the public JamV1 interpreter.
// @@PvmReference={"input":"pvm-control.bin","suite":"pvm_conditional_control_reference"}
use polkavm::{
    BackendKind, CacheModel, CostModelKind, GasMeteringKind, InterruptKind, Module, ModuleConfig,
    ProgramBlob, ProgramCounter, ProgramParts, RawInstance, Reg, SetCacheSizeLimitArgs,
};
use polkavm_common::program::{interpreter_calculate_cache_size, InstructionSetKind};
fn word(data: &[u8], at: usize, width: usize) -> u64 {
    // Callers prove extents first; fixed words are at most eight bytes.
    let mut value = 0;
    for index in 0..width {
        value |= u64::from(data[at + index]) << (8 * index);
    }
    value
}
fn main() {
    let path = std::env::args()
        .nth(1)
        .expect("provide a PVMCTL01 corpus path");
    let data = std::fs::read(path).unwrap();
    assert!(data.len() >= 12 && &data[..8] == b"PVMCTL01");
    let count = word(&data, 8, 4) as usize;
    assert!((384..=4096).contains(&count));
    let engine = ragnarok_memory_probe::engine(false);
    let mut cursor = 12;
    for row in 0..count {
        assert!(data.len() - cursor >= 217);
        let length = word(&data, cursor, 4) as usize;
        let exit = data[cursor + 4];
        let pc = word(&data, cursor + 5, 4) as u32;
        assert!(exit <= 1 && length <= 64);
        let initial: [u64; 13] =
            std::array::from_fn(|index| word(&data, cursor + 9 + index * 8, 8));
        let expected: [u64; 13] =
            std::array::from_fn(|index| word(&data, cursor + 113 + index * 8, 8));
        cursor += 217;
        assert!(length <= data.len() - cursor);
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = data[cursor..cursor + length].to_vec().into();
        cursor += length;
        let blob = ProgramBlob::from_parts(parts).unwrap();
        // Meter the reference so a regression that creates a loop fails instead of hanging the tool.
        let mut profile = ModuleConfig::new();
        profile.set_gas_metering(Some(GasMeteringKind::Sync));
        profile.set_cost_model(Some(CostModelKind::Full(CacheModel::L2Hit)));
        let module = Module::from_blob(&engine, &profile, blob).unwrap();
        let mut instance = module.instantiate().unwrap();
        for (index, value) in initial.into_iter().enumerate() {
            instance.set_reg(Reg::from_raw(index as u32).unwrap(), value);
        }
        instance.set_gas(10000);
        instance.set_next_program_counter(ProgramCounter(0));
        let interrupt = instance.run().unwrap();
        if exit == 0 {
            assert!(matches!(interrupt, InterruptKind::Finished), "row={row}");
        } else {
            assert!(matches!(interrupt, InterruptKind::Trap), "row={row}");
            assert_eq!(
                instance.program_counter(),
                Some(ProgramCounter(pc)),
                "row={row}"
            );
        }
        for (index, value) in expected.into_iter().enumerate() {
            assert_eq!(
                instance.reg(Reg::from_raw(index as u32).unwrap()),
                value,
                "row={row} register={index}"
            );
        }
    }
    assert_eq!(cursor, data.len());
    if engine.backend() == BackendKind::Interpreter {
        check_lazy_jam_branch();
    }
    println!("PolkaVM control-flow cross-check passed: {count}");
}

// Restore the branch inputs before each independent entry, including any suspended cache check.
fn prepare_lazy_jam_case(instance: &mut RawInstance, start: u32, taken: bool) {
    for index in 0..13 {
        let value = match index {
            0 => 0xffff0000,
            1 => {
                if taken {
                    2
                } else {
                    3
                }
            }
            2 => 2,
            7 | 8 => 99,
            _ => 0,
        };
        instance.set_reg(Reg::from_raw(index).unwrap(), value);
    }
    instance.set_gas(100);
    instance.set_next_program_counter(ProgramCounter(start));
}

// Compare the traced or untraced entry to the independent PVMCTL01 branch witness.
fn check_lazy_jam_case(
    instance: &mut RawInstance,
    start: u32,
    taken: bool,
    traced: bool,
    expected_gas: i64,
) {
    let mut steps = Vec::new();
    let mut finished = false;
    for _ in 0..6 {
        match instance.run().unwrap() {
            InterruptKind::Step => steps.push(instance.program_counter().unwrap()),
            InterruptKind::Finished => {
                finished = true;
                break;
            }
            other => panic!("unexpected JamV1 branch interrupt: {other:?}"),
        }
    }
    assert!(
        finished,
        "JamV1 branch did not finish within its source span"
    );
    let (expected_steps, expected_regs): (&[u32], [u64; 13]) = if start == 12 {
        (
            &[12, 15],
            [0xffff0000, 2, 2, 0, 0, 0, 0, 99, 42, 0, 0, 0, 0],
        )
    } else if taken {
        (
            &[0, 3, 12, 15],
            [0xffff0000, 2, 2, 0, 0, 0, 0, 7, 42, 0, 0, 0, 0],
        )
    } else {
        (
            &[0, 3, 7, 10],
            [0xffff0000, 3, 2, 0, 0, 0, 0, 7, 21, 0, 0, 0, 0],
        )
    };
    if traced {
        assert_eq!(
            steps,
            expected_steps
                .iter()
                .copied()
                .map(ProgramCounter)
                .collect::<Vec<_>>()
        );
    } else {
        assert!(steps.is_empty());
    }
    assert_eq!(instance.program_counter(), None);
    for (index, expected) in expected_regs.into_iter().enumerate() {
        assert_eq!(
            instance.reg(Reg::from_raw(index as u32).unwrap()),
            expected,
            "register {index} changed after JamV1 branch at PC {start}"
        );
    }
    assert_eq!(instance.gas(), expected_gas);
}

// Require each rejected cache operation to preserve the pending execution and resident handlers.
fn check_cache_policy_rejection(
    instance: &mut RawInstance,
    cap: SetCacheSizeLimitArgs,
    traced: bool,
) {
    prepare_lazy_jam_case(instance, 12, true);
    let state = |instance: &RawInstance| {
        (
            instance.gas(),
            instance.program_counter(),
            instance.next_program_counter(),
            instance.interpreter_cache_size(),
        )
    };
    let before = state(instance);
    assert!(before.3.unwrap() > 0);
    assert!(instance
        .set_interpreter_cache_size_limit(Some(cap))
        .is_err());
    assert_eq!(state(instance), before);
    if !traced {
        // Untraced Sync isolates the metering restriction on both cache operations.
        assert!(instance.reset_interpreter_cache().is_err());
        assert_eq!(state(instance), before);
    }
    check_lazy_jam_case(instance, 12, true, traced, 98);
}

// Check lazy compilation, cache policy and both independent gas profiles for the same wire.
fn check_lazy_jam_branch() {
    // PC 0 loads A7; PC 3 compares A0 with two. The two exits write distinct A1 values.
    // The exact bridge uses naive Sync fuel; the extra GP Full/L2Hit control prices
    // the branch block at 20 and either exit block at 22.
    const WIRE: [u8; 23] = [
        0, 0, 17, 51, 7, 7, 81, 17, 2, 9, 51, 8, 21, 50, 0, 51, 8, 42, 50, 0, 0x89, 0x94, 0,
    ];
    let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
    parts.code_and_jump_table = WIRE.to_vec().into();
    let blob = ProgramBlob::from_parts(parts).unwrap();
    let engine = ragnarok_memory_probe::engine(true);
    let mut profile = ModuleConfig::new();
    profile.set_page_size(4096);
    profile.set_dynamic_paging(true);
    profile.set_step_tracing(true);
    profile.set_gas_metering(Some(GasMeteringKind::Sync));
    let module = Module::from_blob(&engine, &profile, blob.clone()).unwrap();
    let mut instance = module.instantiate().unwrap();
    let mut sizes = Vec::new();
    for taken in [false, true, true, false] {
        prepare_lazy_jam_case(&mut instance, 0, taken);
        check_lazy_jam_case(&mut instance, 0, taken, true, 96);
        sizes.push(instance.interpreter_cache_size());
    }
    let [Some(first), Some(second), Some(third), Some(fourth)] = sizes.as_slice() else {
        panic!("the selected interpreter did not expose its cache size");
    };
    assert!(
        second > first,
        "the deferred branch arm was not compiled on first take"
    );
    assert_eq!(third, second);
    assert_eq!(fourth, third);

    // Each block has two instructions. Seven handler entries allow four before eviction,
    // enough for the branch and first arm but too few for both arms.
    let cap = SetCacheSizeLimitArgs {
        max_block_size: 2,
        max_cache_size_bytes: interpreter_calculate_cache_size(7),
    };
    check_cache_policy_rejection(&mut instance, cap, true);

    profile.set_step_tracing(false);
    let sync_module = Module::from_blob(&engine, &profile, blob.clone()).unwrap();
    let mut sync = sync_module.instantiate().unwrap();
    prepare_lazy_jam_case(&mut sync, 0, false);
    check_lazy_jam_case(&mut sync, 0, false, false, 96);
    check_cache_policy_rejection(&mut sync, cap, false);

    // Compare two untraced, unmetered instances over the same finite program.
    profile.set_gas_metering(None);
    let cache_module = Module::from_blob(&engine, &profile, blob.clone()).unwrap();
    let mut uncapped = cache_module.instantiate().unwrap();
    let mut bounded = cache_module.instantiate().unwrap();
    bounded.set_interpreter_cache_size_limit(Some(cap)).unwrap();
    let cache_size = |instance: &RawInstance| instance.interpreter_cache_size().unwrap();
    let mut warm_size = 0;
    for (start, taken) in [(0, false), (12, true), (0, true), (0, false)] {
        for instance in [&mut uncapped, &mut bounded] {
            prepare_lazy_jam_case(instance, start, taken);
            check_lazy_jam_case(instance, start, taken, false, 100);
        }
        assert!(cache_size(&bounded) <= cap.max_cache_size_bytes);
        if start == 12 {
            // Entering the other arm from outside must evict handlers only in the capped instance.
            assert!(cache_size(&bounded) < warm_size);
            assert!(cache_size(&uncapped) > warm_size);
        } else if warm_size == 0 {
            // Start both instances with the same live handlers before exercising outside entry.
            warm_size = cache_size(&bounded);
            assert!(warm_size > 0);
            assert_eq!(cache_size(&uncapped), warm_size);
        }
    }

    // Independently check the same decoded branches against the paper's block
    // prices; the maintained bridge still owns its protocol gas in Nim.
    let mut paper = ModuleConfig::new();
    paper.set_page_size(4096);
    paper.set_dynamic_paging(true);
    paper.set_step_tracing(true);
    paper.set_gas_metering(Some(GasMeteringKind::Sync));
    paper.set_cost_model(Some(CostModelKind::Full(CacheModel::L2Hit)));
    let paper_module = Module::from_blob(&engine, &paper, blob).unwrap();
    let mut paper_instance = paper_module.instantiate().unwrap();
    for taken in [false, true] {
        prepare_lazy_jam_case(&mut paper_instance, 0, taken);
        check_lazy_jam_case(&mut paper_instance, 0, taken, true, 58);
    }
    prepare_lazy_jam_case(&mut paper_instance, 12, true);
    check_lazy_jam_case(&mut paper_instance, 12, true, true, 78);
}
