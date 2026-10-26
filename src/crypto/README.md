# Cryptographic primitives and transcripts

[Source guide](../README.md) · [Crypto guide](../../docs/crypto.md)

This folder provides typed primitive results and the protocol-specific transcript/commitment
composition that uses them.

| Module | Responsibility |
| --- | --- |
| [`validator_keys.nim`](validator_keys.nim) | JIP-5 domain-separated validator keys and full-width development seeds |
| [`primitives.nim`](primitives.nim) | Raw-byte Blake2b-256, legacy Keccak-256, Ed25519 and owned signing-seed handling |
| [`assurance_context.nim`](assurance_context.nim) | Assurance transcripts and validator-key/parent verification |
| [`guarantee.nim`](guarantee.nim) | Guarantee signing transcripts over caller-validated report bytes |
| [`extrinsic_commitment.nim`](extrinsic_commitment.nim) | Header extrinsic commitments over the prescribed family projections |

Primitive calls borrow input synchronously and return owned bytes. The narrow
[C bridge](../../native/crypto/README.md) supplies maintained cryptographic operations; JAM domains,
codec composition and acceptance policy stay in Nim. VRF and RingVRF primitives live in the
adjacent [Bandersnatch folder](../bandersnatch/README.md).

See the [crypto contract](../../spec/crypto.md), [assurance contract](../../spec/assurance-crypto.md)
and [signing-domain audit](../../spec/signing-domains.md) for pinned inputs and verification.
The exceptional-point Ed25519 acceptance policy remains an explicit specification gate; observed
backend behavior is not a replacement protocol rule.
