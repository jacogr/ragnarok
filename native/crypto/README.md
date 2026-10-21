# Cryptographic C bridge

[Native bridges](../README.md) · [Nim crypto layer](../../src/crypto/README.md)

[`primitive_bridge.c`](primitive_bridge.c) implements the raw-byte ABI declared in
[`primitive_bridge.h`](primitive_bridge.h): Blake2b-256, Ed25519 public-key derivation/signing/
verification, legacy Keccak-256 and explicit caller-storage wiping.

The bridge uses maintained pinned BoringSSL and XKCP sources. Calls borrow buffers synchronously,
retain no caller pointers and expose fixed-size outputs only on success. Secret signing scratch
is cleansed before return. JAM signing domains, serialized transcripts, codec composition and
protocol acceptance policy belong to the Nim caller.

[`build_crypto.py`](../../tools/build_crypto.py) validates pinned sources and builds the shared
library under `build/crypto/`; [`crypto-pins.json`](../../spec/crypto-pins.json) records dependency
identities and fixture inputs. Make owns setup and build sequencing.

The [crypto contract](../../spec/crypto.md) and [crypto guide](../../docs/crypto.md) describe
primitive vectors, refusal/secret-wipe witnesses, ownership and the unresolved exceptional-point
Ed25519 policy gate. Test observers belong to the verification harness and are not the production ABI.
