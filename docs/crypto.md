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

Bandersnatch now uses pristine ark-vrf 0.2.2, the draft-29 release's explicit reference, with its
nonce updates and unchanged 96/784-byte wire contracts. Draft-29 vectors and published JAM 0.8.0
tickets pass. The draft text's 16-byte challenge conflicts with the reference's 32-byte challenge;
that exact-text parity gate remains documented. Rust stays limited to primitives, with locked
source/SRS hashes and no upstream patches or unsafe test-vector features. Nim owns domain
construction and ring policy.

The exceptional-point Ed25519 acceptance policy is unresolved: pinned BoringSSL accepts the
identity-A/identity-R/zero-S probes. Vector success does not finalize consensus verification policy
or establish a backend audit. See [the primitive contract](../spec/crypto.md) and
[Bandersnatch contract](../spec/bandersnatch.md) for provenance and remaining security limits.
