# Cryptographic primitives

[Design overview](../design.md). Detailed feature contracts live in `spec/`; routine increments
update their feature contract rather than appending progress here.

`src/crypto/` composes domains and codecs around narrow maintained primitive ABIs. The locked
Rust library provides hashes, ordinary Ed25519 signing and explicit ZIP215 verification alongside
the release-designated ark-vrf 0.2.2 Bandersnatch backend. BoringSSL retains QUIC/TLS support; current ordinary verification uses ZIP215. See [the primitive contract](../../spec/crypto.md) for provider
pins and the coordinated protocol activation boundary.
