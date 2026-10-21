// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Public metered host suspend/resume observations, including signed immediate identifier bits.
use polkavm::{
    BackendKind, CacheModel, Config, CostModelKind, Engine, GasMeteringKind, InterruptKind, Module,
    ModuleConfig, ProgramBlob, ProgramCounter, ProgramParts, Reg,
};
use polkavm_common::program::InstructionSetKind;
fn main() {
    let cases: Vec<(Vec<u8>, u32)> = vec![
        (vec![], 0),
        (vec![0], 0),
        (vec![127], 127),
        (vec![128], 0xffffff80),
        (vec![128, 0], 128),
        (vec![0, 128], 0xffff8000),
        (vec![255, 255, 255, 127], 0x7fffffff),
        (vec![0, 0, 0, 128], 0x80000000),
        (vec![255, 255, 255, 255], 0xffffffff),
    ];
    let mut config = Config::default();
    config.set_backend(Some(BackendKind::Interpreter));
    let engine = Engine::new(&config).unwrap();
    let mut count = 0;
    for (tail, id) in cases {
        let mut first = vec![10];
        first.extend(&tail);
        let groups = [
            vec![51, 7, 7],
            first,
            vec![100, 137],
            vec![10, 13],
            vec![100, 138],
            vec![50, 0],
        ];
        let mut code = Vec::new();
        let mut starts = Vec::new();
        for group in groups {
            starts.push(code.len());
            code.extend(group);
        }
        let mut mask = vec![0_u8; code.len().div_ceil(8)];
        for start in starts {
            mask[start / 8] |= 1 << (start % 8);
        }
        let mut wire = vec![0_u8, 0, code.len() as u8];
        wire.extend(code);
        wire.extend(mask);
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = wire.into();
        let blob = ProgramBlob::from_parts(parts).unwrap();
        let mut profile = ModuleConfig::new();
        profile.set_gas_metering(Some(GasMeteringKind::Sync));
        profile.set_cost_model(Some(CostModelKind::Full(CacheModel::L2Hit)));
        let module = Module::from_blob(&engine, &profile, blob).unwrap();
        assert_eq!(module.calculate_gas_cost_for(ProgramCounter(0)), Some(103));
        let mut instance = module.instantiate().unwrap();
        for index in 0..13 {
            let value = match index {
                0 => polkavm::RETURN_TO_HOST,
                7 => 99,
                8 => 77,
                9 => 88,
                10 => 89,
                _ => 0,
            };
            instance.set_reg(Reg::from_raw(index).unwrap(), value);
        }
        instance.set_gas(110);
        instance.set_next_program_counter(ProgramCounter(0));
        assert!(matches!(instance.run().unwrap(),InterruptKind::Ecalli(actual) if actual==id));
        assert_eq!(instance.program_counter(), Some(ProgramCounter(3)));
        assert_eq!(instance.gas(), 7);
        assert_eq!(instance.reg(Reg::A0), 7);
        assert_eq!(instance.reg(Reg::A1), 77);
        instance.set_reg(Reg::A1, 41);
        assert!(matches!(instance.run().unwrap(), InterruptKind::Ecalli(13)));
        assert_eq!(
            instance.program_counter(),
            Some(ProgramCounter((6 + tail.len()) as u32))
        );
        assert_eq!(instance.gas(), 7);
        assert_eq!(instance.reg(Reg::A1), 41);
        assert_eq!(instance.reg(Reg::from_raw(9).unwrap()), 41);
        instance.set_reg(Reg::A1, 42);
        assert!(matches!(instance.run().unwrap(), InterruptKind::Finished));
        assert_eq!(instance.gas(), 7);
        for index in 0..13 {
            let expected = match index {
                0 => polkavm::RETURN_TO_HOST,
                7 => 7,
                8 | 10 => 42,
                9 => 41,
                _ => 0,
            };
            assert_eq!(instance.reg(Reg::from_raw(index).unwrap()), expected);
        }
        count += 1;
    }
    println!("PolkaVM metered host-resumption passed: {count}; cost103 and remaining7");
}
