// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Public parser bounds at the exact code-byte and declared jump-entry limits.
use polkavm::{ProgramBlob, ProgramParts};
use polkavm_common::program::{ISA_JamV1, InstructionSetKind};
fn main() {
    let mut count = 0;
    for (mut wire, accepted) in [
        (vec![224_u8, 255, 255, 255], true),
        (vec![225, 0, 0, 0], true),
        (vec![225, 1, 0, 0], false),
        (vec![255; 9], false),
    ] {
        wire.extend([0, 1, 0, 1]);
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = wire.into();
        let parsed = ProgramBlob::from_parts(parts);
        assert_eq!(parsed.is_ok(), accepted);
        if let Ok(blob) = parsed {
            assert_eq!(blob.code(), &[0]);
            assert_eq!(blob.jump_table().len(), 0);
            assert!(blob.validate_code_with_isa(ISA_JamV1).is_ok());
        }
        count += 1;
    }
    for (size, header) in [
        (33554431_usize, [225_u8, 255, 255, 255]),
        (33554432, [226, 0, 0, 0]),
        (33554433, [226, 1, 0, 0]),
    ] {
        let mut wire = vec![0_u8, 0];
        wire.extend(header);
        let masks = size.div_ceil(8);
        wire.resize(6 + size + masks, 0);
        wire[6 + size..].fill(255);
        if size % 8 != 0 {
            *wire.last_mut().unwrap() = (1 << (size % 8)) - 1;
        }
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = wire.into();
        let parsed = ProgramBlob::from_parts(parts);
        assert_eq!(parsed.is_ok(), size <= 33554432);
        if let Ok(blob) = parsed {
            assert_eq!(blob.code().len(), size);
            assert!(blob.validate_code_with_isa(ISA_JamV1).is_ok());
        }
        count += 1;
    }
    println!("PolkaVM module-limit observations passed: {count}; code33554432 entries16777216");
}
