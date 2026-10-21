// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Public JamV1 parsing and execution observations for GP-PVM-005/006.
// @@PvmReference={"suite":"pvm_jump_table_reference"}
use polkavm::{
    InterruptKind, Module, ModuleConfig, ProgramBlob, ProgramCounter, ProgramParts, Reg,
};
use polkavm_common::program::{ISA_JamV1, InstructionSetKind};
fn main() {
    let engine = ragnarok_memory_probe::engine(false);
    let mut rejected = 0;
    let mut trapped = 0;
    let mut hosted = 0;
    for width in 0_u8..=255 {
        for count in 0_u8..=1 {
            // Same literal code/mask and zero entries as the independent native GP witness.
            let mut wire = vec![count, width, 4];
            wire.resize(3 + usize::from(count) * usize::from(width), 0);
            wire.extend([10, 0, 50, 8, 5]);
            let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
            parts.code_and_jump_table = wire.into();
            let parsed = ProgramBlob::from_parts(parts);
            if width > 4 {
                let error = parsed.err().expect("width above four must fail parsing");
                assert!(error.to_string().contains("invalid jump table entry size"));
                rejected += 1;
                continue;
            }
            let blob = parsed.unwrap();
            assert!(blob.validate_code_with_isa(ISA_JamV1).is_ok());
            let has_entry = count == 1 && width != 0;
            assert_eq!(blob.jump_table().len(), u32::from(has_entry));
            assert_eq!(
                blob.jump_table().get_by_index(0),
                if has_entry {
                    Some(ProgramCounter(0))
                } else {
                    None
                }
            );
            let module = Module::from_blob(&engine, &ModuleConfig::new(), blob).unwrap();
            let mut instance = module.instantiate().unwrap();
            instance.set_reg(Reg::A1, 2);
            instance.set_next_program_counter(ProgramCounter(2));
            let exit = instance.run().unwrap();
            if has_entry {
                assert!(matches!(exit, InterruptKind::Ecalli(0)));
                assert_eq!(instance.program_counter(), Some(ProgramCounter(0)));
                hosted += 1;
            } else {
                assert!(matches!(exit, InterruptKind::Trap));
                assert_eq!(instance.program_counter(), Some(ProgramCounter(2)));
                trapped += 1;
            }
            assert_eq!(instance.reg(Reg::A1), 2);
        }
    }
    assert_eq!((rejected, trapped, hosted), (502, 6, 4));
    println!("PolkaVM jump-table observations passed: 512; rejected={rejected} trapped={trapped} hosted={hosted}");
}
