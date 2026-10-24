// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Checked project entry appended to the recorded unchanged upstream algorithm.
#[polkavm_derive::polkavm_export]
#[no_mangle]
pub extern "C" fn run_checked(limit: u32) -> u32 {
    assert!(limit == 1000 || limit == 100000);
    let state = unsafe { &mut STATE };
    state.memory.resize(limit as usize, 0);
    benchmark_run(core::hint::black_box(state));
    assert_eq!(state.memory[0], 0);
    for &byte in &state.memory[1..] { assert_eq!(byte, 1); }
    (state.memory.len() - 1) as u32
}
