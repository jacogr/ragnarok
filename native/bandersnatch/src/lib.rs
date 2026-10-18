// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Synchronous maintained primitive ABI for the GP 0.8.0 release-designated ark-vrf 0.2.2 profile.
//! No protocol domain/codec logic or dependency source patches. All outputs commit only on success.
//!
//! Exposes bs_* C ABI functions for owned keys/setups, signing, verification and ring
//! commitments; Rust allocations remain behind opaque handles.
use ark_vrf::{
    reexports::ark_serialize::{CanonicalDeserialize, CanonicalSerialize},
    suites::bandersnatch as bs,
};
use std::{
    ffi::c_void,
    panic::{AssertUnwindSafe, catch_unwind},
    slice,
};

/// Owned immutable ring parameters; only this bridge knows the concrete Rust allocation/layout.
struct Setup {
    params: bs::RingProofParams,
    requested: usize,
}
/// ABI reason codes; zero alone succeeds, with no default output bytes on failure.
type Outcome = Result<(), u32>;
/// Catch unwinding backend failures at every fallible ABI entry; allocator aborts are not unwind panics.
fn guard(body: impl FnOnce() -> Outcome) -> u32 {
    // Normal failures preserve their typed reason; Rust unwinds must never cross C.
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(Ok(())) => 0,       // Only completed primitive operations publish output.
        Ok(Err(code)) => code, // Validation/equation failures keep their reason.
        Err(_) => 6,           // An unwind is contained at the Rust boundary.
    }
}
/// Borrow a bounded caller byte range synchronously; C callers must provide genuinely live storage.
unsafe fn bytes<'a>(ptr: *const u8, len: usize) -> Result<&'a [u8], u32> {
    // Empty input has no element address; bound messages before constructing a Rust slice.
    if len == 0 {
        return Ok(&[]);
    }
    // Length is a primitive research resource budget, not a codec/protocol transform.
    if ptr.is_null() || len > 65536 {
        return Err(1);
    }
    Ok(unsafe { slice::from_raw_parts(ptr, len) })
}
/// Decode exactly one canonical compressed value, rejecting appended bytes and malformed subgroup encodings.
fn decode<T: CanonicalDeserialize>(mut input: &[u8]) -> Result<T, u32> {
    let value = T::deserialize_compressed(&mut input).map_err(|_| 2u32)?;
    // Backend decoders can accept suffixes; this ABI never does.
    if !input.is_empty() {
        return Err(1);
    }
    Ok(value)
}
/// Serialize into private scratch of an exact ABI width, then publish one complete value.
unsafe fn publish<T: CanonicalSerialize>(value: &T, output: *mut u8, width: usize) -> Outcome {
    // Missing destinations must fail before writing anything.
    if output.is_null() {
        return Err(1);
    }
    let mut scratch = Vec::new();
    value.serialize_compressed(&mut scratch).map_err(|_| 5u32)?;
    // An unexpected dependency wire size is a backend failure, not truncation.
    if scratch.len() != width {
        return Err(5);
    }
    unsafe {
        std::ptr::copy_nonoverlapping(scratch.as_ptr(), output, width);
    }
    Ok(())
}
/// Borrow a live immutable bridge key; native callers must not forge, race destruction or reuse freed handles.
unsafe fn key<'a>(handle: *const c_void) -> Result<&'a bs::Secret, u32> {
    // Defaults cannot act as an all-zero secret scalar.
    if handle.is_null() {
        return Err(3);
    }
    Ok(unsafe { &*handle.cast::<bs::Secret>() })
}
/// Borrow one live ring owner; params are immutable and may be shared only while their owner remains alive.
unsafe fn setup<'a>(handle: *const c_void) -> Result<&'a Setup, u32> {
    // Nil owners have no initialized trusted SRS/domain parameters.
    if handle.is_null() {
        return Err(3);
    }
    Ok(unsafe { &*handle.cast::<Setup>() })
}
/// Hash-to-curve from raw context data, never from a caller-chosen curve point.
fn input(data: &[u8]) -> Result<bs::Input, u32> {
    bs::Input::new(data).ok_or(2)
}
/// Decode a bounded ordered ring; guard backend truncation before indexing/proving.
fn ring(data: &[u8], owner: &Setup) -> Result<Vec<bs::AffinePoint>, u32> {
    // Require complete points and at least one member within the explicitly requested capacity.
    if data.is_empty() || data.len() % 32 != 0 || data.len() / 32 > owner.requested {
        return Err(1);
    }
    let mut points = Vec::new();
    // Invalid-member substitution is native-language policy, not an implicit Rust rewrite.
    for encoded in data.chunks_exact(32) {
        let public: bs::Public = decode(encoded)?;
        // Historical indexing must never receive an identity member; do not silently rewrite a valid point.
        if public.0.is_zero() {
            return Err(2);
        }
        points.push(public.0);
    }
    Ok(points)
}
/// Import an exact canonical nonzero secret scalar (not a seed); the backend zeroizes it on owner drop.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bs_key_new(data: *const u8, len: usize, out: *mut *mut c_void) -> u32 {
    guard(|| {
        // The out-handle is committed only after all validation and construction completes.
        if len != 32 || out.is_null() {
            return Err(1);
        }
        let secret: bs::Secret = decode(unsafe { bytes(data, len)? })?;
        // Explicit zero-scalar rejection prevents an identity signing key in this research owner API.
        if *secret.scalar() == bs::ScalarField::from(0u64) {
            return Err(2);
        }
        unsafe {
            *out = Box::into_raw(Box::new(secret)).cast();
        }
        Ok(())
    })
}
/// Release one native key owner; aliases become invalid and must never be used or released afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bs_key_free(handle: *mut c_void) {
    // Nil releases are harmless; valid Secret::drop explicitly zeroizes its scalar.
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle.cast::<bs::Secret>()));
        }
    }
}
/// Derive canonical owned public bytes without exposing the backend's mutable key fields.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bs_public(handle: *const c_void, out: *mut u8) -> u32 {
    guard(|| unsafe { publish(&key(handle)?.public(), out, 32) })
}
/// Sign raw context and separate additional data into the original output||c||s 96-byte wire value.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bs_sign(
    handle: *const c_void,
    data: *const u8,
    len: usize,
    ad: *const u8,
    ad_len: usize,
    out: *mut u8,
) -> u32 {
    guard(|| {
        use ark_vrf::ietf::Prover;
        let secret = unsafe { key(handle)? };
        let i = input(unsafe { bytes(data, len)? })?;
        let o = secret.output(i);
        let proof = secret.prove(i, o, unsafe { bytes(ad, ad_len)? });
        unsafe { publish(&(o, proof), out, 96) }
    })
}
/// Verify ordinary contextual proof and return the first 32 output-hash bytes only after successful verification.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bs_verify(
    pk: *const u8,
    sig: *const u8,
    sig_len: usize,
    data: *const u8,
    len: usize,
    ad: *const u8,
    ad_len: usize,
    out: *mut u8,
) -> u32 {
    guard(|| {
        use ark_vrf::ietf::Verifier;
        // Full widths and a live destination are checked before decoding any untrusted proof.
        if sig_len != 96 || out.is_null() {
            return Err(1);
        }
        let public: bs::Public = decode(unsafe { bytes(pk, 32)? })?;
        let (o, proof): (bs::Output, bs::IetfProof) = decode(unsafe { bytes(sig, sig_len)? })?;
        // Historical verifier identities need explicit adapter guards against trivial zero-key/output proofs.
        if public.0.is_zero() || o.0.is_zero() {
            return Err(2);
        }
        public
            .verify(
                input(unsafe { bytes(data, len)? })?,
                o,
                unsafe { bytes(ad, ad_len)? },
                &proof,
            )
            .map_err(|_| 4u32)?;
        let hash = o.hash();
        unsafe {
            std::ptr::copy_nonoverlapping(hash.as_ptr(), out, 32);
        }
        Ok(())
    })
}
/// Build immutable domain parameters from the pinned public ceremony SRS embedded at compile time.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bs_setup_new(size: usize, out: *mut *mut c_void) -> u32 {
    guard(|| {
        // Bound capacity before the historical backend's power-of-two arithmetic or SRS trimming.
        if size == 0 || size > 1023 || out.is_null() {
            return Err(1);
        }
        const SRS: &[u8] = include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../vendor/bandersnatch-vrf-spec/assets/srs/zcash-srs-2-11-uncompressed.bin"
        ));
        // The runner checks the embedded trusted file's immutable hash; validate its curve points too.
        let pcs = bs::PcsParams::deserialize_uncompressed(SRS).map_err(|_| 5u32)?;
        let params = bs::RingProofParams::from_pcs_params(size, pcs).map_err(|_| 5u32)?;
        unsafe {
            *out = Box::into_raw(Box::new(Setup {
                params,
                requested: size,
            }))
            .cast();
        }
        Ok(())
    })
}
/// Release exactly one immutable setup owner; copied native pointers do not gain independent ownership.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bs_setup_free(handle: *mut c_void) {
    // A missing setup allocation has nothing to destroy.
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle.cast::<Setup>()));
        }
    }
}
/// Commit an ordered valid ring, producing the GP 144-byte compressed root with no retained member pointers.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bs_commit(
    handle: *const c_void,
    pks: *const u8,
    len: usize,
    out: *mut u8,
) -> u32 {
    guard(|| {
        let owner = unsafe { setup(handle)? };
        let points = ring(unsafe { bytes(pks, len)? }, owner)?;
        let root = owner.params.verifier_key(&points).commitment();
        unsafe { publish(&root, out, 144) }
    })
}
/// Prove membership for an in-range index matching the signing key, with separate raw context/additional data.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bs_ring_sign(
    handle: *const c_void,
    secret: *const c_void,
    index: usize,
    pks: *const u8,
    pks_len: usize,
    data: *const u8,
    len: usize,
    ad: *const u8,
    ad_len: usize,
    out: *mut u8,
) -> u32 {
    guard(|| {
        use ark_vrf::ring::Prover;
        let owner = unsafe { setup(handle)? };
        let secret = unsafe { key(secret)? };
        let points = ring(unsafe { bytes(pks, pks_len)? }, owner)?;
        // The backend can wrap/truncate indices; the adapter rejects invalid membership before proving.
        if index >= points.len() || points[index] != secret.public().0 {
            return Err(1);
        }
        let prover = owner.params.prover(owner.params.prover_key(&points), index);
        let i = input(unsafe { bytes(data, len)? })?;
        let o = secret.output(i);
        let proof = secret.prove(i, o, unsafe { bytes(ad, ad_len)? }, &prover);
        unsafe { publish(&(o, proof), out, 784) }
    })
}
/// Verify root-bound RingVRF and expose its 32-byte output hash only after both membership and VRF checks.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bs_ring_verify(
    handle: *const c_void,
    root: *const u8,
    sig: *const u8,
    sig_len: usize,
    data: *const u8,
    len: usize,
    ad: *const u8,
    ad_len: usize,
    out: *mut u8,
) -> u32 {
    guard(|| {
        use ark_vrf::ring::Verifier;
        // The exact proof width and output must be checked before invoking historical proof deserializers.
        if sig_len != 784 || out.is_null() {
            return Err(1);
        }
        let owner = unsafe { setup(handle)? };
        let root: bs::RingCommitment = decode(unsafe { bytes(root, 144)? })?;
        let (o, proof): (bs::Output, bs::RingProof) = decode(unsafe { bytes(sig, sig_len)? })?;
        // Output identity is outside this research adapter profile; reject before historical verification.
        if o.0.is_zero() {
            return Err(2);
        }
        let verifier = owner
            .params
            .verifier(owner.params.verifier_key_from_commitment(root));
        bs::Public::verify(
            input(unsafe { bytes(data, len)? })?,
            o,
            unsafe { bytes(ad, ad_len)? },
            &proof,
            &verifier,
        )
        .map_err(|_| 4u32)?;
        let hash = o.hash();
        unsafe {
            std::ptr::copy_nonoverlapping(hash.as_ptr(), out, 32);
        }
        Ok(())
    })
}

/// Validate canonical prime-subgroup public encoding; ring membership additionally forbids identity in this adapter.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bs_validate_public(pk: *const u8, len: usize) -> u32 {
    guard(|| {
        // A complete encoded point is required before subgroup checking.
        if len != 32 {
            return Err(1);
        }
        let _: bs::Public = decode(unsafe { bytes(pk, len)? })?;
        Ok(())
    })
}
/// Export the suite padding point; invalid-key substitution remains native-language application policy.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bs_padding(out: *mut u8) -> u32 {
    guard(|| unsafe {
        publish(
            &<bs::BandersnatchSha512Ell2 as ark_vrf::ring::RingSuite>::PADDING,
            out,
            32,
        )
    })
}

// Private primitive-boundary regression checks; no upstream test-vector feature is enabled.
#[cfg(test)]
mod tests {
    use super::*;
    /// Additional data must change the nonce even when secret and VRF input are unchanged.
    #[test]
    fn additional_data_separates_nonces() {
        use ark_vrf::ietf::Prover;
        let secret = bs::Secret::from_scalar(bs::ScalarField::from(7u64));
        let input = bs::Input::new(b"ragnarok-nonce-regression").unwrap();
        let output = secret.output(input);
        let first = secret.prove(input, output, b"first-additional-data");
        let second = secret.prove(input, output, b"second-additional-data");
        // Recover only these public test-key nonces algebraically; the old backend reused them.
        let first_nonce = first.s - first.c * secret.scalar();
        let second_nonce = second.s - second.c * secret.scalar();
        assert_ne!(first_nonce, second_nonce);
        // Proofs still expose the same VRF output, with the GP's fixed wire width.
        assert_eq!(output.compressed_size() + first.compressed_size(), 96);
    }

    /// A deliberately panicking primitive path must become an ABI reason, never unwind across C.
    #[test]
    fn catches_unwind() {
        assert_eq!(guard(|| panic!("public test panic")), 6);
    }
    /// The canonical decoder must reject a complete valid value with appended bytes.
    #[test]
    fn rejects_suffix() {
        let mut scalar = [0u8; 33];
        scalar[0] = 1;
        assert!(decode::<bs::Secret>(&scalar).is_err());
    }
}
