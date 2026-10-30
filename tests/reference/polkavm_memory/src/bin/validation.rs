// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Public-API module validation, execution and declared standard-stack boundary qualification.
// @@PvmReference={"suite":"pvm_initialization"}
use polkavm::{
    CompileError, Engine, InterruptKind, Module, ModuleConfig, ProgramBlob, ProgramCounter,
    ProgramParts, Reg,
};
use polkavm_common::program::{asm, ISA_JamV1, InstructionSetKind};
use polkavm_common::writer::ProgramBlobBuilder;

/// Prove that resident allocation growth never exposes bytes below a declared three-page stack.
/// This public standard-memory profile differs from the dynamic-paging runtime bridge.
fn declared_stack_bounds(engine: &Engine) {
    let page_size = 4096_u32;
    let mut builder = ProgramBlobBuilder::new(InstructionSetKind::JamV1);
    builder.set_stack_size(3 * page_size);
    builder.add_export_by_basic_block(0, b"load");
    builder.add_export_by_basic_block(1, b"store");
    builder.set_code(
        &[
            asm::load_indirect_u64(Reg::A1, Reg::A0, 0),
            asm::ret(),
            asm::store_indirect_u64(Reg::A1, Reg::A0, 0),
            asm::ret(),
        ],
        &[],
    );
    let blob = ProgramBlob::parse(builder.to_vec().unwrap().into()).unwrap();
    let mut profile = ModuleConfig::new();
    profile.set_page_size(page_size);
    profile.set_dynamic_paging(false);
    let module = Module::from_blob(engine, &profile, blob).unwrap();
    let exports: Vec<_> = module
        .exports()
        .map(|export| export.program_counter())
        .collect();
    assert_eq!(exports.len(), 2);
    let memory = module.memory_map();
    let low = memory.stack_address_low();
    let high = memory.stack_address_high();
    assert_eq!(memory.stack_size(), 3 * page_size);
    assert_eq!(high - low, 3 * page_size);
    let mut instance = module.instantiate().unwrap();
    let markers = [(high - 1, 0x11), (high - page_size - 1, 0x22), (low, 0x33)];
    for (address, value) in markers {
        // Successively growing to the non-power-of-two lower bound must retain all older bytes.
        instance.write_memory(address, &[value]).unwrap();
    }
    for (address, value) in markers {
        // Every marker remains accessible at its declared address after the last growth.
        assert_eq!(instance.read_memory(address, 1).unwrap(), vec![value]);
    }
    for address in [low - 1, low - 8, low - page_size] {
        // Host reads and writes must refuse even after capacity has rounded above the declared size.
        assert!(
            instance.read_memory(address, 1).is_err(),
            "below-stack host read {address:#x}"
        );
        assert!(
            instance.write_memory(address, &[0xff]).is_err(),
            "below-stack host write {address:#x}"
        );
    }
    for address in [low, low + page_size, high - 8] {
        // Both real guest instructions succeed throughout the declared stack, including its endpoints.
        let value = 0x1234_5678_9abc_def0_u64;
        instance.set_reg(Reg::RA, polkavm::RETURN_TO_HOST);
        instance.set_reg(Reg::A0, u64::from(address));
        instance.set_reg(Reg::A1, value);
        instance.set_next_program_counter(exports[1]);
        assert!(matches!(instance.run().unwrap(), InterruptKind::Finished));
        assert_eq!(
            instance.read_memory(address, 8).unwrap(),
            value.to_le_bytes()
        );
        instance.set_reg(Reg::A1, 0);
        instance.set_next_program_counter(exports[0]);
        assert!(matches!(instance.run().unwrap(), InterruptKind::Finished));
        assert_eq!(instance.reg(Reg::A1), value);
    }
    for address in [low - 4, low - 8, low - page_size] {
        for &pc in &exports {
            // Crossing or starting below the declared boundary traps for both guest load and store.
            instance.set_reg(Reg::RA, polkavm::RETURN_TO_HOST);
            instance.set_reg(Reg::A0, u64::from(address));
            instance.set_next_program_counter(pc);
            assert!(
                matches!(instance.run().unwrap(), InterruptKind::Trap),
                "below-stack guest {address:#x}"
            );
        }
    }
    println!("Declared stack bounds passed: 3 pages; host and guest positive/refusal controls");
}

fn main() {
    // Select the same public interpreter profile used by the other reference tools.
    let engine = ragnarok_memory_probe::engine(false);
    declared_stack_bounds(&engine);
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
