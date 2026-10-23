// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Project-owned checked entry; the upstream sieve implementation above is unchanged.
#[polkavm_derive::polkavm_export]
#[no_mangle]
pub extern "C" fn run_checked(limit: u32) -> u32 {
    assert!(limit >= 100 && limit <= 10_000_000);
    let sieve = run_sieve(limit as usize);
    let count = sieve.count_primes();
    assert_eq!(primes::PrimeValidator.is_valid(limit as usize, count), Some(true));
    count as u32
}
