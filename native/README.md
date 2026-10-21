# Native bridges

[Project overview](../README.md) · [Source guide](../src/README.md) ·
[Pinned dependencies](../docs/dependencies.md)

Project-owned C and Rust interfaces connect Nim to maintained upstream primitives and transport
libraries. Protocol behavior stays in [`src/`](../src/README.md); upstream source trees are pinned
under [`vendor/`](../vendor/README.md). Each folder's README describes its ABI, ownership and build
contracts.

| Directory | Summary |
| --- | --- |
| [`bandersnatch/`](bandersnatch/README.md) | Rust VRF/RingVRF primitive bridge and locked Cargo dependencies |
| [`crypto/`](crypto/README.md) | C hash, Ed25519 and secret-wiping primitives |
| [`quic/`](quic/README.md) | LSQUIC transport and copied TLS certificate observations |

Use `make setup` to provision dependencies and `make` to build the development proof peer.
[`tools/`](../tools/README.md) owns orchestration; generated libraries and compiler output stay
under ignored `build/`.
