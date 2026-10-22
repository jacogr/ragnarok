// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Ordinary hash/signature primitives sharing the existing locked Rust backend.
//! Borrow caller storage synchronously, contain unwinds, and publish only completed outputs.
use blake2::{Blake2b, digest::consts::U32};
use ed25519_zebra::{Signature, SigningKey, VerificationKey};
use sha3::{Digest, Keccak256};
use std::{
    panic::{AssertUnwindSafe, catch_unwind},
    slice,
};
use zeroize::{Zeroize, Zeroizing};

/// Translate validation failures and contained unwinds to the established C boolean result.
fn guarded(body: impl FnOnce() -> Option<()>) -> i32 {
    i32::from(matches!(catch_unwind(AssertUnwindSafe(body)), Ok(Some(()))))
}

/// Caller guarantees live storage; reject missing/nonrepresentable ranges before forming a slice.
unsafe fn borrowed<'a>(input: *const u8, length: usize) -> Option<&'a [u8]> {
    // Empty messages need no address, even when represented by NULL.
    if length == 0 {
        return Some(&[]);
    }
    // Rust slices cannot exceed isize::MAX; no VRF-specific message cap applies to hashes.
    if input.is_null() || length > isize::MAX as usize {
        return None;
    }
    Some(unsafe { slice::from_raw_parts(input, length) })
}

/// Copy one complete public output only after all fallible operations have succeeded.
unsafe fn publish(output: *mut u8, value: &[u8]) -> Option<()> {
    // The C caller owns enough writable bytes for the declared fixed output width.
    if output.is_null() {
        return None;
    }
    unsafe {
        std::ptr::copy_nonoverlapping(value.as_ptr(), output, value.len());
    }
    Some(())
}

/// Parameterized 32-byte Blake2b, rather than a truncated 64-byte digest.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rcr_blake2b256(data: *const u8, length: usize, out: *mut u8) -> i32 {
    guarded(|| unsafe { publish(out, &Blake2b::<U32>::digest(borrowed(data, length)?)) })
}

/// Legacy Keccak-256 uses suffix 0x01, independently of SHA3-256.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rcr_keccak256(data: *const u8, length: usize, out: *mut u8) -> i32 {
    guarded(|| unsafe { publish(out, &Keccak256::digest(borrowed(data, length)?)) })
}

/// Derive a public key while explicit drop guards erase the owned seed and expanded signing key.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rcr_ed_public(seed: *const u8, out: *mut u8) -> i32 {
    guarded(|| unsafe {
        let seed = Zeroizing::new(<[u8; 32]>::try_from(borrowed(seed, 32)?).ok()?);
        let key = Zeroizing::new(SigningKey::from(*seed));
        let public: [u8; 32] = VerificationKey::from(&*key).into();
        publish(out, &public)
    })
}

/// Ordinary deterministic Ed25519 over the exact raw message; no domain or prehash is added.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rcr_ed_sign(
    seed: *const u8,
    data: *const u8,
    length: usize,
    out: *mut u8,
) -> i32 {
    guarded(|| unsafe {
        let message = borrowed(data, length)?;
        let seed = Zeroizing::new(<[u8; 32]>::try_from(borrowed(seed, 32)?).ok()?);
        let key = Zeroizing::new(SigningKey::from(*seed));
        publish(out, &key.sign(message).to_bytes())
    })
}

/// ZIP215 acceptance is explicit; the C shim owns protocol selection without a verifier fallback.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rcr_ed_verify_zip215(
    key: *const u8,
    sig: *const u8,
    data: *const u8,
    length: usize,
) -> i32 {
    guarded(|| unsafe {
        let key = VerificationKey::try_from(borrowed(key, 32)?).ok()?;
        let signature = Signature::from(<[u8; 64]>::try_from(borrowed(sig, 64)?).ok()?);
        key.verify(&signature, borrowed(data, length)?).ok()
    })
}

/// Explicit erasure uses zeroize's optimizer-resistant implementation; no caller pointer is kept.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rcr_wipe(data: *mut u8, length: usize) {
    // Default/empty owners have no live byte range; C callers guarantee writable storage otherwise.
    if !data.is_null() && length <= isize::MAX as usize {
        unsafe {
            slice::from_raw_parts_mut(data, length).zeroize();
        }
    }
}
