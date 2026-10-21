// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Compare representable gas edges and explicitly reject positive unsigned-to-signed reinterpretation.
// @@PvmReference={"suite":"pvm_gas_domain_reference"}
use polkavm::{
    CacheModel, CostModelKind, GasMeteringKind, InterruptKind, Module, ModuleConfig, ProgramBlob,
    ProgramCounter, ProgramParts, Reg,
};
use polkavm_common::program::InstructionSetKind;

// Public Gas is i64; upper-half u64 values are conversion controls, never substituted negative inputs.
fn main() {
    let engine = ragnarok_memory_probe::engine(false);
    let mut profile = ModuleConfig::new();
    profile.set_gas_metering(Some(GasMeteringKind::Sync));
    profile.set_cost_model(Some(CostModelKind::Full(CacheModel::L2Hit)));
    let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
    parts.code_and_jump_table = vec![0, 0, 1, 0, 1].into();
    let module =
        Module::from_blob(&engine, &profile, ProgramBlob::from_parts(parts).unwrap()).unwrap();
    assert_eq!(module.calculate_gas_cost_for(ProgramCounter(0)), Some(2));
    for available in [0_u64, 1, 2, 47, 48, 49, i64::MAX as u64 - 1, i64::MAX as u64] {
        // Every common-domain edge executes the identical original trap blob with unchanged high-bit registers.
        let mut instance = module.instantiate().unwrap();
        for r in 0..13 {
            instance.set_reg(Reg::from_raw(r).unwrap(), u64::MAX - u64::from(r));
        }
        instance.set_gas(i64::try_from(available).unwrap());
        instance.set_next_program_counter(ProgramCounter(0));
        let observed = instance.run().unwrap();
        if available < 2 {
            assert_eq!(observed, InterruptKind::NotEnoughGas);
        } else {
            assert_eq!(observed, InterruptKind::Trap);
        }
        assert_eq!(instance.gas(), i64::try_from(if available < 2 { available } else { available - 2 }).unwrap());
        assert_eq!(instance.program_counter(), Some(ProgramCounter(0)));
        for r in 0..13 {
            assert_eq!(instance.reg(Reg::from_raw(r).unwrap()), u64::MAX - u64::from(r));
        }
    }
    for available in [1_u64 << 63, (1_u64 << 63) + 1, u64::MAX - 1, u64::MAX] {
        // No public positive gas value exists for these inputs; truncating/casting would test a different state.
        assert!(polkavm::Gas::try_from(available).is_err());
    }
    println!("PolkaVM gas-domain checks passed: 8 shared inputs, 4 out-of-domain controls");
}
