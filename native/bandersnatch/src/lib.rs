// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Synchronous maintained primitive ABI for the current Gray Paper Draft 35 Thin v1 profile.
//! No protocol domain/codec logic or dependency source patches. All outputs commit only on success.
//!
//! Exposes bs_* C ABI functions for owned keys/setups, signing, verification and ring
//! commitments; Rust allocations remain behind opaque handles.
mod primitives;

use ark_vrf::{
    reexports::ark_serialize::{CanonicalDeserialize, CanonicalSerialize},
    suites::bandersnatch as bs,
};
use std::{
    ffi::c_void,
    panic::{AssertUnwindSafe, catch_unwind},
    slice,
};
use zeroize::Zeroizing;

/// Owned immutable ring parameters; only this bridge knows the concrete Rust allocation/layout.
struct Setup {
    params: bs::RingSetup,
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
/// Finite primitive message budget covers full contextual signatures without interpreting protocol bytes.
const MAX_INPUT_BYTES: usize = 128 * 1024;

/// Borrow a bounded caller byte range synchronously; C callers must provide genuinely live storage.
unsafe fn bytes<'a>(ptr: *const u8, len: usize) -> Result<&'a [u8], u32> {
    // Empty input has no element address; bound messages before constructing a Rust slice.
    if len == 0 {
        return Ok(&[]);
    }
    // Length is a primitive research resource budget, not a codec/protocol transform.
    if ptr.is_null() || len > MAX_INPUT_BYTES {
        return Err(1);
    }
    Ok(unsafe { slice::from_raw_parts(ptr, len) })
}
/// Decode exactly one canonical compressed value, rejecting appended bytes and malformed subgroup encodings.
fn decode<T: CanonicalDeserialize + CanonicalSerialize>(mut input: &[u8]) -> Result<T, u32> {
    let original = input;
    let value = T::deserialize_compressed(&mut input).map_err(|_| 2u32)?;
    // Backend decoders can accept suffixes; this ABI never does.
    if !input.is_empty() {
        return Err(1);
    }
    // Composite pairing types require explicit validity checks in this dependency profile.
    value.check().map_err(|_| 2u32)?;
    let mut canonical = Vec::new();
    value
        .serialize_compressed(&mut canonical)
        .map_err(|_| 5u32)?;
    // Exclude alternative representations accepted by a foreign type's decoder.
    if canonical != original {
        return Err(2);
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
    bs::Input::new(data).map_err(|_| 2u32)
}
/// Decode a bounded ordered ring; guard backend truncation before indexing/proving.
fn ring(data: &[u8], owner: &Setup) -> Result<Vec<bs::Public>, u32> {
    // Require complete points and at least one member within the explicitly requested capacity.
    if data.is_empty() || data.len() % 32 != 0 || data.len() / 32 > owner.requested {
        return Err(1);
    }
    let mut points = Vec::new();
    // Invalid-member substitution is native-language policy, not an implicit Rust rewrite.
    for encoded in data.chunks_exact(32) {
        let public: bs::Public = decode(encoded)?;
        // Checked Public decoding rejects identity; normalization never substitutes that valid curve point.
        points.push(public);
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
/// Import a 32-byte seed using Draft 35 A.3 and the pinned Bandersnatch v1 suite.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bs_key_from_seed(
    data: *const u8,
    len: usize,
    out: *mut *mut c_void,
) -> u32 {
    guard(|| {
        // Validate width and destinations before borrowing; publish only a complete owned key.
        if len != 32 || out.is_null() {
            return Err(1);
        }
        let mut seed = Zeroizing::new([0u8; 32]);
        seed.copy_from_slice(unsafe { bytes(data, len)? });
        let secret = bs::Secret::from_seed(*seed);
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
/// Sign raw context and separate additional data into the Thin output||R||s 96-byte wire value.
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
        let secret = unsafe { key(handle)? };
        let i = input(unsafe { bytes(data, len)? })?;
        let o = secret.output(i);
        let proof = secret.prove_thin(
            ark_vrf::VrfIo {
                input: i,
                output: o,
            },
            unsafe { bytes(ad, ad_len)? },
        );
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
        // Full widths and a live destination are checked before decoding any untrusted proof.
        if sig_len != 96 || out.is_null() {
            return Err(1);
        }
        let public: bs::Public = decode(unsafe { bytes(pk, 32)? })?;
        let (o, proof): (bs::Output, bs::ThinProof) = decode(unsafe { bytes(sig, sig_len)? })?;
        public
            .verify_thin(
                ark_vrf::VrfIo {
                    input: input(unsafe { bytes(data, len)? })?,
                    output: o,
                },
                unsafe { bytes(ad, ad_len)? },
                &proof,
            )
            .map_err(|_| 4u32)?;
        let hash = o.hash::<32>();
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
        let params = bs::RingSetup::from_pcs_params(size, pcs).map_err(|_| 5u32)?;
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
        let root = owner
            .params
            .verifier_key(&points)
            .map_err(|_| 2u32)?
            .commitment();
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
        let owner = unsafe { setup(handle)? };
        let secret = unsafe { key(secret)? };
        let points = ring(unsafe { bytes(pks, pks_len)? }, owner)?;
        // The backend can wrap/truncate indices; the adapter rejects invalid membership before proving.
        if index >= points.len() || points[index] != secret.public() {
            return Err(1);
        }
        let prover_key = owner.params.prover_key(&points).map_err(|_| 2u32)?;
        let prover = owner.params.ring_context().ring_prover(prover_key, index);
        let i = input(unsafe { bytes(data, len)? })?;
        let o = secret.output(i);
        let proof = bs::RingProof::prove(
            ark_vrf::VrfIo {
                input: i,
                output: o,
            },
            unsafe { bytes(ad, ad_len)? },
            secret,
            &prover,
        );
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
        // The exact proof width and output must be checked before invoking historical proof deserializers.
        if sig_len != 784 || out.is_null() {
            return Err(1);
        }
        let owner = unsafe { setup(handle)? };
        let root: bs::RingCommitment = decode(unsafe { bytes(root, 144)? })?;
        let (o, proof): (bs::Output, bs::RingProof) = decode(unsafe { bytes(sig, sig_len)? })?;
        let verifier = owner
            .params
            .ring_context()
            .ring_verifier(owner.params.verifier_key_from_commitment(root));
        proof
            .verify(
                ark_vrf::VrfIo {
                    input: input(unsafe { bytes(data, len)? })?,
                    output: o,
                },
                unsafe { bytes(ad, ad_len)? },
                &verifier,
            )
            .map_err(|_| 4u32)?;
        let hash = o.hash::<32>();
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
        // Preserve identity as a valid subgroup point, never silently substitute it as padding.
        // Actual signing/ring verification decodes Public and rejects identity separately.
        let _: bs::AffinePoint = decode(unsafe { bytes(pk, len)? })?;
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
    /// Seed imports reject malformed ABI arguments without modifying an existing output slot.
    #[test]
    fn seed_import_boundaries() {
        let seed = [0u8; 33];
        let sentinel = 1usize as *mut c_void;
        for length in [0, 31, 33] {
            let mut handle = sentinel;
            assert_eq!(
                unsafe { bs_key_from_seed(seed.as_ptr(), length, &mut handle) },
                1
            );
            assert_eq!(handle, sentinel);
        }
        let mut handle = sentinel;
        assert_eq!(
            unsafe { bs_key_from_seed(std::ptr::null(), 32, &mut handle) },
            1
        );
        assert_eq!(handle, sentinel);
        assert_eq!(
            unsafe { bs_key_from_seed(seed.as_ptr(), 32, std::ptr::null_mut()) },
            1
        );
        // An all-zero input seed is valid entropy for the primitive, unlike a zero scalar import.
        let mut handle = std::ptr::null_mut();
        assert_eq!(
            unsafe { bs_key_from_seed(seed.as_ptr(), 32, &mut handle) },
            0
        );
        assert!(!handle.is_null());
        unsafe { bs_key_free(handle) };
    }

    /// Additional data binds the Thin proof while leaving the VRF output unchanged.
    #[test]
    fn additional_data_separates_proofs() {
        let secret = bs::Secret::from_scalar(bs::ScalarField::from(7u64));
        let io = secret.vrf_io(bs::Input::new(b"ragnarok-nonce-regression").unwrap());
        let first = secret.prove_thin(io, b"first-additional-data");
        let second = secret.prove_thin(io, b"second-additional-data");
        let mut first_bytes = Vec::new();
        let mut second_bytes = Vec::new();
        first.serialize_compressed(&mut first_bytes).unwrap();
        second.serialize_compressed(&mut second_bytes).unwrap();
        assert_ne!(first_bytes, second_bytes);
        assert!(
            secret
                .public()
                .verify_thin(io, b"second-additional-data", &first)
                .is_err()
        );
        assert!(
            secret
                .public()
                .verify_thin(io, b"first-additional-data", &first)
                .is_ok()
        );
        assert_eq!(io.output.compressed_size() + first.compressed_size(), 96);
    }

    /// Large contextual signatures succeed through the exact ABI; excess inputs leave every output untouched.
    #[test]
    fn bounded_large_additional_data() {
        let secret = bs::Secret::from_scalar(bs::ScalarField::from(7u64));
        let handle = (&secret as *const bs::Secret).cast();
        let context = b"ragnarok-large-header-regression";
        let additional = vec![0x5au8; MAX_INPUT_BYTES + 1];
        let mut public = Vec::new();
        secret.public().serialize_compressed(&mut public).unwrap();
        // Exercise the reproduced full epoch sizes, combined marker envelope, and exact primitive ceiling.
        for length in [65547usize, 65739, 118276, MAX_INPUT_BYTES] {
            let mut signature = [0xa5u8; 96];
            let status = unsafe {
                bs_sign(
                    handle,
                    context.as_ptr(),
                    context.len(),
                    additional.as_ptr(),
                    length,
                    signature.as_mut_ptr(),
                )
            };
            assert_eq!(status, 0);
            let mut output = [0xa5u8; 32];
            let status = unsafe {
                bs_verify(
                    public.as_ptr(),
                    signature.as_ptr(),
                    signature.len(),
                    context.as_ptr(),
                    context.len(),
                    additional.as_ptr(),
                    length,
                    output.as_mut_ptr(),
                )
            };
            assert_eq!(status, 0);
            // A changed AD byte remains bound even at the largest accepted length.
            let mut changed = additional[..length].to_vec();
            changed[length - 1] ^= 1;
            output.fill(0xa5);
            let status = unsafe {
                bs_verify(
                    public.as_ptr(),
                    signature.as_ptr(),
                    signature.len(),
                    context.as_ptr(),
                    context.len(),
                    changed.as_ptr(),
                    changed.len(),
                    output.as_mut_ptr(),
                )
            };
            assert_eq!(status, 4);
            assert_eq!(output, [0xa5u8; 32]);
            // Preserve a canonical proof so oversized-input checks are not masked by malformed proof rejection.
            let valid_signature = signature;
            // Both oversize AD and oversize context reject before publishing any signature or output.
            for (data, ad) in [
                (&context[..], &additional[..]),
                (&additional[..], &context[..]),
            ] {
                signature.fill(0xa5);
                let status = unsafe {
                    bs_sign(
                        handle,
                        data.as_ptr(),
                        data.len(),
                        ad.as_ptr(),
                        ad.len(),
                        signature.as_mut_ptr(),
                    )
                };
                assert_eq!(status, 1);
                assert_eq!(signature, [0xa5u8; 96]);
                let status = unsafe {
                    bs_verify(
                        public.as_ptr(),
                        valid_signature.as_ptr(),
                        valid_signature.len(),
                        data.as_ptr(),
                        data.len(),
                        ad.as_ptr(),
                        ad.len(),
                        output.as_mut_ptr(),
                    )
                };
                assert_eq!(status, 1);
                assert_eq!(output, [0xa5u8; 32]);
            }
        }
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
