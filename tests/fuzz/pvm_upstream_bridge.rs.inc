// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

// Appended after the unchanged, pinned upstream Arbitrary definitions and transform_code.
use polkavm::{
    BackendKind, CacheModel, Config, CostModelKind, Engine, GasMeteringKind, InterruptKind,
    MemoryProtection, Module, ModuleConfig, ProgramCounter, ProgramParts,
};
use polkavm_common::program::{ISA_JamV1, InstructionSet, InstructionSetKind, ProgramBlob};
use polkavm_common::writer::ProgramBlobBuilder;

fn main() {
    // Bounded inputs are files from libFuzzer's retained corpus, never executable host code.
    let args: Vec<_> = std::env::args().collect();
    assert_eq!(
        args.len(),
        3,
        "usage: bridge INPUT_DIRECTORY OUTPUT_DIRECTORY"
    );
    let mut config = Config::default();
    config.set_backend(Some(BackendKind::Interpreter));
    config.set_allow_dynamic_paging(true);
    let engine = Engine::new(&config).unwrap();
    assert_eq!(engine.backend(), BackendKind::Interpreter);
    std::fs::create_dir_all(&args[2]).unwrap();
    let mut inputs: Vec<_> = std::fs::read_dir(&args[1])
        .unwrap()
        .map(|e| e.unwrap().path())
        .collect();
    inputs.sort();
    for input in inputs {
        // Reject before reading an unbounded extent; names are generated SHA-256 identities.
        assert!(input.is_file() && std::fs::metadata(&input).unwrap().len() <= 4096);
        let name = input.file_name().unwrap().to_str().unwrap();
        let bytes = std::fs::read(&input).unwrap();
        let Ok((ops, cache)) = <(Vec<OperationKind>, Option<CacheSizeConfig>)>::arbitrary(
            &mut arbitrary::Unstructured::new(&bytes),
        ) else {
            println!("{name}\tskipped-arbitrary");
            continue;
        };
        if ops.len() > 256 {
            println!("{name}\tskipped-operation-limit");
            continue;
        }
        let code = transform_code(ops);
        if code
            .iter()
            .any(|i| ISA_JamV1.opcode_to_raw(i.opcode(), 0).is_none())
        {
            println!("{name}\tskipped-non-jam-opcode");
            continue;
        }
        // JamV1 serializes the original instruction operands, with a documented terminal trap.
        // JamV1 requires a physical final terminator, including after a final conditional/fallthrough.
        let mut code = code;
        code.push(asm::trap());
        let mut builder = ProgramBlobBuilder::new(InstructionSetKind::JamV1);
        builder.add_export_by_basic_block(0, b"main");
        builder.set_code(&code, &[]);
        let serialized = builder.into_vec().unwrap();
        let wire = ProgramParts::from_bytes(serialized.clone().into())
            .unwrap()
            .code_and_jump_table;
        assert!(wire.len() <= 8192);
        let blob = ProgramBlob::parse(serialized.into()).unwrap();
        let mut module_config = ModuleConfig::default();
        module_config.set_page_size(4096);
        module_config.set_dynamic_paging(true);
        module_config.set_gas_metering(Some(GasMeteringKind::Sync));
        module_config.set_cost_model(Some(CostModelKind::Full(CacheModel::L2Hit)));
        let module = Module::from_blob(&engine, &module_config, blob).unwrap();
        for profile in 0..2 {
            // Both profiles are explicit JAM adaptations. Profile 1 exercises mapped indirect memory.
            let mut instance = module.instantiate().unwrap();
            let mut regs = [0_u64; 13];
            regs[0] = polkavm::RETURN_TO_HOST;
            if profile == 1 {
                regs = [
                    polkavm::RETURN_TO_HOST,
                    0x11000,
                    0x10000,
                    0x10fff,
                    0x11ffc,
                    1,
                    u64::MAX,
                    0x80000000,
                    63,
                    32,
                    0x12345678,
                    0x10001,
                    0,
                ];
            }
            for (reg, value) in Reg::ALL.into_iter().zip(regs) {
                instance.set_reg(reg, value);
            }
            let initial: Vec<u8> = (0..8192).map(|i| (i * 17 + 3) as u8).collect();
            instance
                .zero_memory_with_memory_protection(0x10000, 8192, MemoryProtection::ReadWrite)
                .unwrap();
            instance.write_memory(0x10000, &initial).unwrap();
            instance.set_gas(512);
            instance.set_next_program_counter(ProgramCounter(0));
            let exit = instance.run().unwrap();
            let (tag, fault) = match exit {
                InterruptKind::NotEnoughGas => (1, 0),
                InterruptKind::Trap => (2, 0),
                InterruptKind::Finished => (3, 0),
                InterruptKind::Segfault(f) => (4, f.page_address),
                other => panic!("unexpected bridge interrupt: {other:?}"),
            };
            assert!(instance.gas() >= 0);
            let mut frame = b"PVMFUZ01".to_vec();
            frame.extend_from_slice(&(wire.len() as u32).to_le_bytes());
            frame.extend_from_slice(&512_u64.to_le_bytes());
            frame.push(tag);
            frame.extend_from_slice(&(instance.gas() as u64).to_le_bytes());
            frame.extend_from_slice(
                &instance
                    .program_counter()
                    .map(|p| u64::from(p.0))
                    .unwrap_or(u64::MAX)
                    .to_le_bytes(),
            );
            frame.extend_from_slice(&fault.to_le_bytes());
            for value in regs {
                frame.extend_from_slice(&value.to_le_bytes());
            }
            for reg in Reg::ALL {
                frame.extend_from_slice(&instance.reg(reg).to_le_bytes());
            }
            assert_eq!(frame.len(), 249);
            frame.extend_from_slice(&wire);
            frame.extend_from_slice(&initial);
            frame.extend_from_slice(&instance.read_memory(0x10000, 8192).unwrap());
            std::fs::write(
                std::path::Path::new(&args[2]).join(format!("{name}-{profile}.bin")),
                frame,
            )
            .unwrap();
        }
        // Cache limits exercise upstream implementation policy only; they are recorded, not guest state.
        let cache = cache
            .map(|c| format!("{},{}", c.max_cache_size_bytes, c.max_block_size))
            .unwrap_or("none".into());
        let opcodes: Vec<_> = code
            .iter()
            .map(|i| {
                ISA_JamV1
                    .opcode_to_raw(i.opcode(), 0)
                    .unwrap()
                    .0
                    .to_string()
            })
            .collect();
        println!(
            "{name}\tbridged\t{}\t{cache}\t{}",
            code.len(),
            opcodes.join(",")
        );
    }
}
