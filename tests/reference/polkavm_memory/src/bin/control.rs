// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Cross-check independent GP conditional-control paths through the public JamV1 interpreter.
// @@PvmReference={"input":"pvm-control.bin","suite":"pvm_conditional_control_reference"}
use polkavm::{
    CacheModel, CostModelKind, GasMeteringKind, InterruptKind, Module, ModuleConfig, ProgramBlob,
    ProgramCounter, ProgramParts, Reg,
};
use polkavm_common::program::InstructionSetKind;
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
    println!("PolkaVM control-flow cross-check passed: {count}");
}
