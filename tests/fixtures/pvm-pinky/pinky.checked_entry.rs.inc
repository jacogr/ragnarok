// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Checked entry runs one complete rendered frame from the frozen initialized NES state.
#[polkavm_derive::polkavm_export]
#[no_mangle]
pub extern "C" fn run_checked(frames: u32) -> u32 {
    assert_eq!(frames, 1);
    let state = unsafe { &mut STATE };
    benchmark_run(core::hint::black_box(state));
    assert_eq!(state.framebuffer.as_ref().unwrap().len(), 256 * 240);
    frames
}
