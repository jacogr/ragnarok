# Cryptographic primitives

[Design overview](../design.md) · [Crypto source map](../../src/crypto/README.md)

Nim owns protocol domains and encoding. The native ABIs supply primitive operations
and resource ownership. [Primitives](../../src/crypto/primitives.nim) own the hash
and Ed25519 contracts. [Bandersnatch](../../src/bandersnatch/bandersnatch.nim) owns
its typed Thin adapter. [Crypto](../../spec/crypto.md) and
[Bandersnatch](../../spec/bandersnatch.md) record provider pins and qualification.
