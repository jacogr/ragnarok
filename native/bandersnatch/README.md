# Bandersnatch Rust bridge

[Native bridges](../README.md) · [Nim adapter](../../src/bandersnatch/README.md)

This folder implements the narrow synchronous primitive ABI for the pinned ark-vrf 0.6.1
Draft 35 Thin v1/RingVRF profile.

| Path | Contents |
| --- | --- |
| [`bridge.h`](bridge.h) | Public C ABI, fixed proof/output widths and opaque key/setup ownership |
| [`src/`](src/) | Rust primitive implementation and maintained adapter regression checks |
| [`Cargo.toml`](Cargo.toml), [`Cargo.lock`](Cargo.lock) | Reviewed Rust feature selection and locked dependency closure |

Rust owns scalar keys and setup allocations; callers release them explicitly. Key destruction
zeroizes retained secret storage. Borrowed buffers live only for a synchronous call, and failures
leave outputs unpublished. The Nim layer supplies typed ownership and protocol domain policy.

The [Bandersnatch pins](../../spec/bandersnatch-pins.json) bind source trees, SRS, fixtures and
Cargo lock bytes. Build orchestration in [`build_bandersnatch.py`](../../tools/build_bandersnatch.py)
validates those inputs and runs locked/offline builds after Make setup. Generated artifacts stay
under `build/bandersnatch/`; upstream sources remain pristine under `vendor/`.

See the [primitive contract](../../spec/bandersnatch.md), [crypto guide](../../docs/crypto.md) and
[folder instructions](AGENTS.md) for verification, exact profile constraints and the documented
v1 hash-to-curve padding discrepancy. Unsafe deterministic/non-ZK vector features must remain disabled.

The same locked library also exports the internal `rcr_*` ordinary-crypto ABI consumed by
`native/crypto/primitive_bridge.c`. It shares SHA-2/SHA3 and zeroization dependencies without
changing this Bandersnatch suite or enabling ark-vrf's unrelated Ed25519 ECVRF feature.
See [the primitive contract](../../spec/crypto.md) for provider pins, ZIP215 activation and
verification coverage. Platform library identities are relocatable; the crypto build colocates
its provider copy. The `bs_*` opaque-owner ABI and reason codes remain unchanged.
