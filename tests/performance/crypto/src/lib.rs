// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Benchmark-only one-shot BLAKE2b-256 adapter with the production ABI's validation/unwind boundary.
use std::panic::{AssertUnwindSafe, catch_unwind};

/// Borrow caller storage synchronously and publish only a complete unkeyed 32-byte digest.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bench_blake2b256(data: *const u8, length: usize, out: *mut u8) -> i32 {
    // Match the maintained primitive bridge's null/size checks before creating a Rust slice.
    if out.is_null() || length > isize::MAX as usize || (length != 0 && data.is_null()) {
        return 0;
    }
    i32::from(
        catch_unwind(AssertUnwindSafe(|| {
            // Empty messages permit NULL, just as the production primitive does.
            let input = if length == 0 {
                &[]
            } else {
                unsafe { std::slice::from_raw_parts(data, length) }
            };
            let hash = blake2b_simd::Params::new().hash_length(32).hash(input);
            unsafe { std::ptr::copy_nonoverlapping(hash.as_bytes().as_ptr(), out, 32) };
        }))
        .is_ok(),
    )
}

/// Report runtime-visible CPU features; expected dispatch is inferred from the pinned crate's policy.
#[unsafe(no_mangle)]
pub extern "C" fn bench_cpu_features() -> u32 {
    let mut features = 0;
    #[cfg(any(target_arch = "x86", target_arch = "x86_64"))]
    {
        // Dynamic checks include operating-system support, rather than build-machine assumptions.
        if std::is_x86_feature_detected!("avx2") {
            features |= 1;
        }
        if std::is_x86_feature_detected!("sse4.1") {
            features |= 2;
        }
    }
    #[cfg(target_arch = "aarch64")]
    {
        // Version 1.0.3 uses its portable implementation on ARM despite NEON availability.
        if std::arch::is_aarch64_feature_detected!("neon") {
            features |= 4;
        }
    }
    features
}
