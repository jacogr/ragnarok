# Cryptographic primitives

[Design overview](../design.md). Detailed feature contracts live in `spec/`; routine increments
update their feature contract rather than appending progress here.

`src/crypto/` composes domains and codecs around narrow maintained primitive ABIs. BoringSSL
provides Blake2b-256 and ordinary Ed25519; XKCP provides legacy Keccak-256. The release-designated ark-vrf 0.2.2
Bandersnatch Rust backend is isolated behind `native/bandersnatch/` and a typed Nim adapter.
