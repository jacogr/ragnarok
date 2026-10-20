# Native bridges

[Project overview](../README.md) · [Source guide](../src/README.md) ·
[Pinned dependencies](../docs/dependencies.md)

Project-owned C and Rust interfaces connect the Nim implementation to maintained upstream
primitives and transport libraries. JAM codecs, domains, identities and state policy stay in
[`src/`](../src/README.md); upstream source trees are pinned under [`vendor/`](../vendor/README.md).

| Directory | Contents |
| --- | --- |
| [`bandersnatch/`](bandersnatch/) | Rust VRF/RingVRF bridge, C header and locked Cargo dependencies |
| [`crypto/`](crypto/) | C adapters for Blake2b-256, Ed25519 and legacy Keccak-256 |
| [`quic/`](quic/) | LSQUIC transport and TLS certificate-field C interfaces |

Use `make setup` to provision dependencies and `make` to build the development proof peer.
[`tools/`](../tools/README.md) owns build orchestration; generated libraries and compiler output
stay under ignored `build/`.

See the [crypto guide](../docs/crypto.md), [networking guide](../docs/networking.md) and
[Bandersnatch contract](../spec/bandersnatch.md) for API scope and verification.
