# Primitive crypto contract

Baseline: unreleased Gray Paper v0.8.0, commit
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
[Cryptography](https://github.com/gavofyork/graypaper/blob/1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d/text/notation.tex#L163).
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

## Current ZIP215 verification policy

The adopted Gray Paper explicitly requires [ZIP215](https://zips.z.cash/zip-0215):
noncanonical point encodings are accepted, S must be below the group order, and the
cofactored signature equation is checked. Both `verify` and `verifyZip215` use the same
maintained Zebra verifier; there is no backend retry or release-policy fallback.
The protocol null validator uses its newly specified invalid Ed25519 encoding.

The independent RFC8032 positives and pinned Wycheproof corpus remain intact. Upstream
Wycheproof case 151 labels x=0 with the sign bit set as invalid under RFC8032; ZIP215
accepts this encoding. This one fixed, documented expectation differs from its upstream
label. See [the exact compatibility record](crypto-zip215-upgrade.md), including historical
BoringSSL witnesses. These are implementation policy differences, not paper discrepancies.
The official JAM vector tree has no standalone primitive corpus; these checks do not prove
complete state-transition/JAM parity.

## Reproducibility and provenance

The existing `native/bandersnatch` locked Rust closure now supplies Blake2b-256
(`blake2` 0.10.6), legacy Keccak (`sha3` 0.10.9), ordinary Ed25519 signing/key derivation
(`ed25519-zebra` 4.2.0), and explicit erasure (`zeroize` 1.9.1). The ark-vrf 0.2.2
Bandersnatch profile and features are unchanged. Its Ed25519 feature is an ECVRF suite,
not an ordinary signature verifier, so enabling it would not supply this API.
Zebra 4.2.0 shares the already locked SHA-2 0.10 closure; Zebra 5 introduces a separate
SHA-2 0.11/curve25519-dalek 5 closure. All registry identities/checksums are locked;
both primitive pin records verify the lock SHA-256. No upstream source is patched.

The C primitive shim forwards only to the locked Rust library. BoringSSL remains a
QUIC/TLS dependency but is absent from primitive compilation and linkage. XKCP is no
longer provisioned. Signing-key/seed owners have explicit zeroizing drop guards; this
does not claim elimination of all compiler/backend-internal secret copies.

Focused native witnesses cover cofactored torsion points, noncanonical A/R encodings,
invalid points, S equal to the group order, normal signatures and altered messages.

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
failure, broader contextual/Bandersnatch parity or Linux behavior. Current ZIP215 activation is covered independently above; Thin VRF parity remains a separate gate.

## Crypto consolidation completion checks

The foundation requires `make unit SUITE=crypto_seeds` (ZIP215 policy and observed seed wipes),
the existing crypto and Bandersnatch corpora, `make unit SUITE=bandersnatch_owners`, the
production `make` link, and `make check-python` / `make format-check`. ABI checks include
missing pointers, nonrepresentable slices, hashes beyond 64 KiB and fresh-process colocated
loading. Local Darwin evidence does not claim exact-head Linux CI or complete JAM parity.
ZIP215 and the null-validator representation advance together in this coordinated pin upgrade.
