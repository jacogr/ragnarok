# M2 cryptography assessment

Assessment date: 2026-10-14. This inventories required primitives and proposes a
bounded first integration round. No crypto adapter has been implemented, no
new library has been installed and no cryptographic conformance run is claimed.
The maintainer has reported that Linux CI passes for the preceding explicit
QUIC-adapter round.

## Pinned requirements

The baseline remains Gray Paper v0.7.1,
`1c979cb59bb800f92ffff083a2701004dfc6cd33`. Requirements are read directly from
[Cryptography in notation.tex](https://github.com/gavofyork/graypaper/blob/1c979cb59bb800f92ffff083a2701004dfc6cd33/text/notation.tex#L155),
[Bandersnatch appendix](https://github.com/gavofyork/graypaper/blob/1c979cb59bb800f92ffff083a2701004dfc6cd33/text/bandersnatch.tex),
[BEEFY](https://github.com/gavofyork/graypaper/blob/1c979cb59bb800f92ffff083a2701004dfc6cd33/text/beefy.tex)
and their references. Exact research revisions and source hashes are recorded
in [crypto-research.json](../spec/crypto-research.json).

| Primitive | Pinned role/shape | Proposed round |
| --- | --- | --- |
| Blake2b-256 | 32-byte hashes of the prescribed raw/encoded octets | First slice |
| Ed25519 | RFC 8032 signing and verification; 32-byte public keys, 64-byte signatures | First slice |
| Keccak-256 | Ethereum-style 32-byte hashing, including BEEFY commitments | Subsequent hashing slice |
| Bandersnatch contextual VRF | 32-byte public keys, 96-byte signatures, 32-byte extracted output | Dedicated compatibility/integration slice |
| Bandersnatch Ring-VRF | 144-byte ring roots, 784-byte proofs, ring commitment and output extraction | Dedicated compatibility/integration slice |
| BLS12-381 signing/aggregation | BEEFY's specified aggregation mechanism; GP public-key type is 144 bytes | Later dedicated slice |

Blake2b must be configured for a 32-byte digest; truncating a Blake2b-512 digest
is a different function. Keccak-256 is not SHA3-256. Context/domain bytes and
codec serialization stay in Nim/Odin rather than being silently selected by a
crypto backend. Bandersnatch context and additional message data have different
roles in the VRF definition and must not be collapsed into an arbitrary single
message hash.

Erasure coding is another native dependency investigation, but its Reed-Solomon
arithmetic is separate from this cryptographic primitive inventory. This round
does not implement erasure coding, state transitions or a validator.

## Same-backend first slice

The existing pinned BoringSSL source already exports:

- `BLAKE2B256`, plus its init/update/final API.
- `ED25519_keypair_from_seed`, `ED25519_sign` and `ED25519_verify`.

These were inspected in the local unmodified native headers at
`vacp2p/boringssl` revision `88341070936d28e08f82db1326c73d67962cd043`.
The primitive APIs also exist in upstream Google BoringSSL:
[Blake2b header](https://boringssl.googlesource.com/boringssl/+/HEAD/include/openssl/blake2.h)
and [Ed25519 header](https://boringssl.googlesource.com/boringssl/+/refs/heads/main/include/openssl/curve25519.h).
Availability is not a claim of an audit of our particular pinned fork/build;
backend provenance and audit scope must be recorded with implementation results.

Recommended first round: **Blake2b-256 and ordinary Ed25519 seed-to-public-key,
signing and verification**, through one small shared primitive C ABI and
separate typed Nim/Odin adapters. Reuse the pinned native crypto build without
QUIC socket/engine setup. This adds no upstream source patch or new library
revision. Keep primitive builds/tests runnable independently from the QUIC test
matrix, even when their dependency preparation is shared.

The API should have:

- Distinct hash, seed, public-key and signature types; explicit checked import
  of external fixed-size bytes.
- Owned output values and synchronous borrowing of inputs, with no retained
  caller pointers or hidden callbacks.
- Typed failed imports/signing operations with no exposed default output;
  verification clearly reports invalid signatures.
- Explicit handling of empty messages, host/native lengths, secret-key scratch
  storage and wiping. Backend-expanded 64-byte private keys must not be confused
  with RFC 8032's 32-byte seed or exposed as public metadata.
- No implicit prehash mode or JAM domain prefix. Ordinary Ed25519 is the pinned
  starting algorithm; Ed25519ph/ctx require a separate explicit contract.
- A recorded thread-safety/ownership model and concurrent calls on independent
  inputs, without introducing a global mutable hash/signing context.

Acceptance should include published Blake2b known-answer cases configured for
32 bytes, empty/block-boundary/large messages, independent Python hashlib
cross-checks, [RFC 8032 section 7.1 vectors](https://www.rfc-editor.org/rfc/rfc8032#section-7.1),
and a pinned relevant adversarial corpus such as
[Wycheproof Ed25519](https://github.com/C2SP/wycheproof/blob/main/testvectors_v1/ed25519_test.json).
Mutated messages/keys/signatures and wrong lengths must fail as expected.
Noncanonical/low-order verification behavior needs an explicit specification
and conformance assessment; a provider's default acceptance policy is not
silently the JAM consensus rule. Add negative compilation checks for type-domain
mixups, cross-language equality and Linux CI using the same pinned backend.

Both languages using one library is not independent validation of that
library. Published vectors and a separate oracle are essential; Nim/Odin
agreement checks their adapters and marshaling. Existing official JAM vector
revision `1dc503af37ae8ecc7b6e24a393f6102801c0c80c` has no standalone crypto
directory in the inspected tree. Its protocol/state vectors can support later
message/crypto integration but do not replace primitive known-answer tests.

## Bandersnatch is an early compatibility gate

The pinned paper references the
[Bandersnatch VRF specification](https://github.com/davxy/bandersnatch-vrf-spec)
and an IETF-VRF formulation. The reviewed
[ark-vrf candidate](https://github.com/davxy/ark-vrf/tree/a49e44efc73868ca9a60dfd1ccb0367f425a2809)
supports Bandersnatch and ring proofs, but its current
[changelog](https://github.com/davxy/ark-vrf/blob/a49e44efc73868ca9a60dfd1ccb0367f425a2809/CHANGELOG.md)
records a 0.6.0 suite change that alters keys, VRF outputs, padding points and
ring commitments. It retains an older suite option. This is evidence that
matching the curve name or choosing the newest crate is insufficient, not a
selection of a compatible suite.

Before selecting that backend, establish the exact compatible specification,
suite/transcript/hash-to-curve behavior, proof/output encodings, padding point,
ring size and setup parameters against pinned independent/JAM vectors. Review
its audit/provenance and dependency lockfile. If a Rust implementation is used,
expose a narrow C ABI to both candidates, pin its Rust toolchain/dependency
closure, and contain panics and allocation failures at that boundary. No Rust
codec or state-transition implementation belongs behind the crypto ABI.

BLS likewise needs the exact BEEFY aggregation/encoding scheme from the cited
paper; generic BLS12-381 support alone does not establish compatibility with
its 144-byte public-key type or aggregate construction. No backend is selected
for Bandersnatch, Keccak or BLS by this assessment.

The first slice establishes ordinary crypto FFI correctness and ergonomics.
It does not complete M2, and its success must not hide the remaining
Bandersnatch/BLS compatibility and audit questions.
