// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Cross-check independent Gray Paper gas expectations against the pinned public pipeline simulator.
// @@PvmReference={"generator":"pvm_gas_reference","suite":"pvm_gas"}
use polkavm::{ProgramBlob, ProgramParts};
use polkavm_common::program::{InstructionSetKind, Instructions};
use polkavm_common::simulator::{CacheModel, Simulator};
use polkavm_common::utils::{GasVisitorT, B64};
// Decode a bounded test-format field after the corresponding header extent is checked.
fn word(data: &[u8], at: usize, width: usize) -> u64 {
    let mut out = 0_u64;
    // Fixed fields are at most eight bytes and never read beyond the validated record.
    for i in 0..width {
        out |= u64::from(data[at + i]) << (i * 8);
    }
    out
}
fn main() {
    // Expectations remain independently generated from the Gray Paper, including local cycle limits.
    let path = std::env::args()
        .nth(1)
        .expect("provide a PVMGAS01 corpus path");
    let data = std::fs::read(path).unwrap();
    assert!(data.len() >= 12 && &data[..8] == b"PVMGAS01");
    let count = word(&data, 8, 4) as usize;
    assert!(count >= 1000);
    let mut cursor = 12;
    // Consume complete length-delimited program blobs and reject truncated records before access.
    for row in 0..count {
        assert!(data.len() - cursor >= 24);
        let start = word(&data, cursor, 4) as u32;
        let expected = word(&data, cursor + 4, 8);
        assert!(word(&data, cursor + 12, 8) > 0);
        let length = word(&data, cursor + 20, 4) as usize;
        cursor += 24;
        assert!(length <= data.len() - cursor);
        // Public raw parts preserve the corpus code/mask bytes and all relative branch offsets.
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = data[cursor..cursor + length].to_vec().into();
        cursor += length;
        let blob = ProgramBlob::from_parts(parts).unwrap();
        let code = blob.code();
        let mask = blob.bitmask();
        let isa = InstructionSetKind::JamV1;
        // L2Hit supplies the paper's fixed 25-cycle memory latency; engine defaults are unrelated.
        let mut simulator = Simulator::<B64, ()>::new(code, isa, CacheModel::L2Hit, ());
        let mut completed = false;
        // Stop at the priced block's first completed terminator, ignoring following code.
        for instruction in Instructions::new_bounded_known_boundary(isa, code, mask, start) {
            instruction.visit_parsing(&mut simulator);
            // The public API exposes block price; native tests retain exact local-cycle-limit checks.
            if let Some(actual) = simulator.take_block_cost() {
                assert_eq!(u64::from(actual), expected, "row={row}");
                completed = true;
                break;
            }
        }
        assert!(completed, "row={row} produced no completed block cost");
    }
    assert_eq!(cursor, data.len());
    println!("PolkaVM JamV1/L2Hit gas cross-check passed: {count} rows");
}
