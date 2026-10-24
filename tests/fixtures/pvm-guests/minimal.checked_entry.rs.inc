// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Checked project entry appended to the recorded unchanged upstream algorithm.
#[polkavm_derive::polkavm_export]
#[no_mangle]
pub extern "C" fn run_checked(limit: u32) -> u32 {
    assert!(limit == 1000 || limit == 100000);
    let state = unsafe { &mut STATE };
    state.counter = 0;
    state.function = dummy_even;
    for _ in 0..limit { benchmark_run(core::hint::black_box(state)); }
    assert_eq!(state.counter, 2 * limit + limit % 2);
    state.counter
}
