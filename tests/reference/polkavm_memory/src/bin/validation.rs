// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Public-API probe separating structural program parsing, code validation and execution.
use polkavm::{
    BackendKind, CompileError, Config, Engine, InterruptKind, Module, ModuleConfig, ProgramBlob,
    ProgramCounter, ProgramParts, Reg,
};
use polkavm_common::program::{ISA_JamV1, InstructionSetKind};
fn main() {
    // Select the same public interpreter profile used by the other reference tools.
    let mut config = Config::default();
    config.set_backend(Some(BackendKind::Interpreter));
    let engine = Engine::new(&config).unwrap();
    // Identical load prefixes isolate the final terminator from other program differences.
    for (name, code) in [
        ("trap_control", vec![51_u8, 7, 7, 0]),
        ("final_fallthrough", vec![51_u8, 7, 7, 1]),
        ("final_conditional", vec![51_u8, 7, 7, 170, 0, 253]),
    ] {
        // Both opcode boundaries are explicit; operand bytes are never marked.
        let mut wire = vec![0_u8, 0, code.len() as u8];
        wire.extend(&code);
        wire.push(9);
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = wire.into();
        let blob = ProgramBlob::from_parts(parts).unwrap();
        let validation = blob.validate_code_with_isa(ISA_JamV1);
        if name == "trap_control" {
            // The matching trap-ending control remains loadable and executes the prefix.
            assert!(validation.is_ok());
        } else {
            // The engine rejects at the missing successor, before an instance can exist.
            assert_eq!(validation, Err(ProgramCounter(code.len() as u32)));
        }
        println!("{name}: validation={validation:?}");
        match Module::from_blob(&engine, &ModuleConfig::new(), blob) {
            Ok(module) => {
                // Only the positive control may execute under this pinned validation policy.
                assert_eq!(name, "trap_control");
                let mut instance = module.instantiate().unwrap();
                instance.set_reg(Reg::A0, 99);
                instance.set_next_program_counter(ProgramCounter(0));
                let interrupt = instance.run().unwrap();
                assert!(matches!(interrupt, InterruptKind::Trap));
                assert_eq!(instance.reg(Reg::A0), 7);
                assert_eq!(instance.program_counter(), Some(ProgramCounter(3)));
                println!("{name}: exit={interrupt:?} a0={}", instance.reg(Reg::A0));
            }
            Err(error) => {
                // These are observed module-validation refusals, not runtime Trap outcomes.
                assert_ne!(name, "trap_control");
                assert!(matches!(&error, CompileError::ValidationFailed(..)));
                println!("{name}: module_error={error}");
            }
        }
    }
    let mut cases = 0;
    // Cover every GP final terminator with empty, short and maximum-length operand tails.
    for opcode in [
        0_u8, 1, 40, 50, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 170, 171, 172, 173, 174, 175,
        180,
    ] {
        let accepted = matches!(opcode, 0 | 40 | 50 | 80 | 180);
        for padding in [0_usize, 1, 24] {
            for unreachable in [false, true] {
                // A leading trap makes the bad suffix unreachable without changing module validity.
                let mut code = vec![if unreachable { 0 } else { 51 }, 7, 7, opcode];
                code.resize(4 + padding, 0);
                let mut wire = vec![0_u8, 0, code.len() as u8];
                wire.extend(&code);
                wire.push(9);
                wire.resize(3 + code.len() + code.len().div_ceil(8), 0);
                let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
                parts.code_and_jump_table = wire.into();
                let blob = ProgramBlob::from_parts(parts).unwrap();
                let validation = blob.validate_code_with_isa(ISA_JamV1);
                assert_eq!(
                    validation.is_ok(),
                    accepted,
                    "opcode={opcode} padding={padding}"
                );
                if !accepted {
                    assert_eq!(validation, Err(ProgramCounter(code.len() as u32)));
                }
                let loaded = Module::from_blob(&engine, &ModuleConfig::new(), blob);
                assert_eq!(loaded.is_ok(), accepted);
                if let Err(error) = loaded {
                    assert!(matches!(error, CompileError::ValidationFailed(..)));
                }
                cases += 1;
            }
        }
    }
    println!("Final terminator matrix passed: {cases}");
}
