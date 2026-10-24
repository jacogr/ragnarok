# Cryptography and ownership

`src/crypto/primitives.nim` wraps the maintained `native/crypto/` ABI. Blake2b-256, legacy
Keccak-256, public keys and signatures have distinct owned byte types. `CryptoResult` defaults
fail; select `error == CryptoError.None` before reading its value. Import validates exact sizes;
verification independently applies the provider's point/signature policy.

`importSeed` retains private acyclic ARC storage; copied handles retain that owner. `clearSeed`
wipes and invalidates aliases, and last-owner destruction wipes remaining seed material. Foreign
borrows are synchronous. Do not clear/use the same mutable owner concurrently; workers use
independent owners. Rust parameter/key owners use corresponding private ARC destructors in
`src/bandersnatch/bandersnatch.nim`.

`guaranteeMessage` hashes canonical report bytes and prepends `$jam_guarantee`.
`assuranceMessage` returns `$jam_available || Blake2b-256(parent || fixed bitfield)` with no inner
length prefix. `verifyAssurances` checks configuration, exact validator-key mapping, all structural
and parent constraints, then signatures. Verified count is not a state-transition or availability verdict.

Bandersnatch uses pristine ark-vrf 0.6.0 with the adopted Gray Paper's Draft 35 Thin v1
profile. Seven Thin and seven RingVRF vectors pass the maintained 96/784-byte ABI; its public
SRS remains unchanged. The vector profile's 48-byte hash-to-curve padding differs from RFC9380;
the separate v2 suite is not selected. Historical IETF ticket passes remain archived and are
not current Thin/STF parity. Rust stays limited to primitives, with locked source/SRS hashes,
no upstream patches, and production column blinding. Nim owns domain construction and ring policy.

The exceptional-point Ed25519 acceptance policy is unresolved: pinned BoringSSL accepts the
identity-A/identity-R/zero-S probes. Vector success does not finalize consensus verification policy
or establish a backend audit. See [the primitive contract](../spec/crypto.md) and
[Bandersnatch contract](../spec/bandersnatch.md) for provenance and remaining security limits.

## Compiler and verification

The supported Nimony adapters use private guarded results and explicit acyclic ARC/native owner
lifetimes. `make check` runs the preserved raw-primitive, assurance, guarantee/report,
release-reference Bandersnatch, native-boundary and concurrency corpora. It also runs bounded
proof offload with worker-local Rust setups and copied inputs. The [compiler record](nimony-trial.md)
retains exact coverage and compiler limitations. Implemented-scope local regression parity does
not settle the draft-text discrepancy, exceptional-point policy or production security audit.
