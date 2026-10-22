# Primitive crypto contract

Baseline: Gray Paper v0.8.0, commit
`07f041dabd073f9018b418e9ee72e79dd2185401`,
[Cryptography](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/notation.tex#L155).
Toolchain/dependency/vector revisions are in [crypto-pins.json](crypto-pins.json).

| Operation | Contract |
| --- | --- |
| Blake2b-256 | Unkeyed raw-byte input, digest length configured as 32 bytes. Never truncate Blake2b-512. |
| Keccak-256 | Legacy Ethereum-style Keccak: rate 1088, capacity 512 bits, suffix 0x01, 32-byte digest. Never SHA3-256's 0x06 suffix. |
| Ed25519 key derivation | Exact 32-byte RFC 8032 seed to 32-byte encoded public key. All-zero seed is valid when explicitly imported. |
| Ed25519 signing | Ordinary deterministic Ed25519 over the exact raw message, 64-byte signature. No implicit domain, prehash, Ed25519ctx or Ed25519ph. |
| Ed25519 verification | Exact 32/64-byte encoded key/signature import, then backend verification. Wrong sizes fail import; correctly sized invalid encodings/signatures return false. |

Domain construction and codec serialization remain caller responsibilities in
Nim. Hashes, keys and signatures have distinct nominal types. Public-key
import proves width/ownership only; it does not assert subgroup membership.
Hash/key/signature values own bytes. Seed handles hide their private retained
copy and cannot silently substitute a default seed. Failed results carry only
a reason; defaults fail. Checked success selection remains enabled in release.

## Verification policy remains an explicit protocol question

[RFC 8032 section 5.1.7](https://www.rfc-editor.org/rfc/rfc8032#section-5.1.7)
allows a cofactored verification equation and a sufficient uncofactored check.
The Nim adapter preserves pinned BoringSSL's actual verifier policy. The independent RFC8032
and 151-case Wycheproof corpus is supplemented by explicit exceptional-point probes. BoringSSL
accepts A=identity, R=identity, S=0 for empty and `abc` messages. It rejects the tested S=group-order
and all-zero A/R, S=0 encodings. These probes are not an exhaustive exceptional-point corpus.

A complete JAM integration still needs an explicit normative decision and
focused independent tests for every exceptional point/canonicality policy. The explicit ZIP215
capability below prepares the forthcoming specification upgrade without changing this release selection.
Do not advertise these backend verdicts as a finalized consensus verifier.
The pinned official JAM vector tree has no standalone primitive-crypto corpus;
RFC/Wycheproof tests are supplemental primitive evidence, not JAM state tests.

## Reproducibility and provenance

The existing `native/bandersnatch` locked Rust closure now supplies Blake2b-256
(`blake2` 0.10.6), legacy Keccak (`sha3` 0.10.9), ordinary Ed25519 signing/key derivation
(`ed25519-zebra` 4.2.0), and explicit erasure (`zeroize` 1.9.1). The ark-vrf 0.2.2
Bandersnatch profile and features are unchanged. Its Ed25519 feature is an ECVRF suite,
not an ordinary signature verifier, so enabling it would not supply this API.
Zebra 4.2.0 shares the already locked SHA-2 0.10 closure; Zebra 5 introduces a separate
SHA-2 0.11/curve25519-dalek 5 closure. All registry identities/checksums are locked;
both primitive pin records verify the lock SHA-256. No upstream source is patched.

The C shim retains BoringSSL for release-policy `verify`; QUIC also still needs BoringSSL.
XKCP is removed from provisioning and linkage. This consolidates primitive providers but
adds the ordinary-signature Rust dependency; it does not remove all native dependencies.
Seed and expanded signing-key owners have explicit zeroizing drop guards. This does not
claim elimination of all compiler/backend-internal secret copies.

### Explicit ZIP215 capability before protocol activation

`verifyZip215` / `rc_ed_verify_zip215` exposes Zebra's maintained
[ZIP215](https://zips.z.cash/zip-0215) verifier. It accepts noncanonical curve encodings,
requires S below the group order, and checks the cofactored equation. It is a separate
explicit operation, never an automatic retry after `verify` fails. The release protocol
continues to call `verify`. The coordinated unreleased Gray Paper upgrade will change that
selection together with the null-validator key; this layer does not advance the GP pin.

Focused native witnesses cover A=all-zero (order four), R=identity, S=0 with empty/one-byte
messages, noncanonical identity A (y=p+1), invalid A=02 followed by zeros, and a failed
identity equation with S=1. Ordinary RFC/Wycheproof behavior remains checked independently.
The all-zero-key witness is an implementation compatibility gap for the upcoming GP rule,
not a Gray Paper discrepancy.

The Rust library has a relocatable platform identity; the crypto shim resolves a colocated
copy through `@loader_path`/`$ORIGIN`. A fresh-process relocation check clears loader-path
environment overrides. Rust ABI inputs reject nonrepresentable slice lengths, allow empty
NULL messages, borrow synchronously, contain unwinds and publish completed outputs only.
Allocator aborts remain process failures. No VRF-specific 64 KiB cap applies to hashes/signing.

Upstream licensing stays with the pristine sources and Cargo package notices. Wycheproof's
fixture/license hashes and RFC 8032 section 7.1 fixtures are unchanged. Functional checks do
not establish an audit or production suitability certification.

## Compiler-port evidence

The numerical/compiler observations below record the original migration increment; see
[testing](../docs/testing.md) for current cumulative coverage and revision-specific CI results.

The [nightly trial](../docs/nimony-trial.md#sixteenth-increment-raw-cryptographic-primitives) ports
the raw adapter without changing primitive parameters, native sources or dependency pins. Results
hide status/payload; error is read-only and value requires success, including for opaque seed
handles. Stable checked nullable references bind seed access to its retained ARC allocation.
The supported destructor erases on final-owner release; explicit clear erases and invalidates aliases.

`tools/test_runtime.py` rebuilds the production bridge and runs the preserved independent equations
with checked ARC/Clang LTO. A separate observer-linked test matches exact seed storage and checks
nonzero-before/zero-after inside the wipe callback while memory is live, never after free. It also
injects backend refusals; those test symbols are absent from the production library. Native worker
checks use independent per-thread seeds and join every successfully started worker on all exits.
This does not establish concurrent clearing/signing of a shared seed, recoverable ARC allocation
failure, broader contextual/Bandersnatch parity or Linux behavior. The exceptional-point policy
above remains an explicit JAM integration gate.

## Crypto consolidation completion checks

The foundation requires `make unit SUITE=crypto_seeds` (ZIP215 policy and observed seed wipes),
the existing crypto and Bandersnatch corpora, `make unit SUITE=bandersnatch_owners`, the
production `make` link, and `make check-python` / `make format-check`. ABI checks include
missing pointers, nonrepresentable slices, hashes beyond 64 KiB and fresh-process colocated
loading. Local Darwin evidence does not claim exact-head Linux CI or complete JAM parity.
The next protocol layer will activate ZIP215 and migrate the null-validator representation
with the authorized unreleased Gray Paper pin.
