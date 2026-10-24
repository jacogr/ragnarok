# Bandersnatch primitives

[Source guide](../README.md) · [Crypto guide](../../docs/crypto.md)

[`bandersnatch.nim`](bandersnatch.nim) is the typed Nim interface to the current Draft 35
ark-vrf 0.6.0 Thin VRF and RingVRF profile. It owns scalar-key and setup handles, validates
fixed encodings, and exposes public-key derivation, signing, verification and ring commitments.
Calls borrow input synchronously; copied outputs and explicit owner lifetimes stay visible to Nim.

The implementation calls the maintained [Rust/C ABI](../../native/bandersnatch/README.md).
Protocol signing domains, invocation policy and codec serialization belong to callers; this
primitive layer does not infer them. The selected profile uses 96-byte Thin signatures and 784-byte
RingVRF proofs, with pinned public SRS and bounded setup capacity.

See the [Bandersnatch contract](../../spec/bandersnatch.md) for vectors, ownership checks and the
recorded executable-profile/RFC padding discrepancy. The
[folder instructions](AGENTS.md) preserve that exact profile and forbid unsafe vector features;
passing the vectors is not an audit claim.
