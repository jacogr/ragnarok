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

## Nimony branch migration

Raw primitives and assurance signing contexts now pass the pinned Nimony trial under checked
ARC/Clang LTO. Assurance results use private discriminators/payloads, read-only errors and guarded
fixed-value accessors. The unchanged 2,087-request independent corpus and four literal checks pass,
alongside 24 actual/default misuse rejections, nine privacy/nominal compilation probes and a native
fixed-copy/preflight/refusal/recovery suite. Live occupancy remains 192 bytes before/after 1,000
warmed scopes; this is scoped evidence, not a general leak claim. Signature acceptance policy and
protocol/dependency pins are unchanged. Linux confirmation remains separate.

Guarantee composition now also passes: `GuaranteeMessageResult` keeps fixed transcript storage
private and guards success access while preserving read-only `.error`/`.value` callers. The full
report driver replays the same 18,430 codec requests and all 63 original independent credential
checks. Known-answer/copy/refusal/recovery tests, four runtime misuse guards and eight compilation
probes also pass; live occupancy remains 192 bytes after 1,000 warmed scopes.

Bandersnatch results, fixed imports and native key/setup owner lifetimes now also pass locally.
Private nullable ARC owners retain aliases, invalidate them on close and release the real Rust
allocation once at final release. A separate observer-linked suite verifies actual allocation/free
counts and constructor refusal/recovery; it neither hides frees nor reads freed secret memory.
The pinned Rust build and three native bridge tests pass, with 32 result guards and 20 compiler
probes in the Nimony runner. Key/import occupancy remains 192 bytes after 1,000 warmed scopes.

The original seven ordinary vectors, seven ring vectors, seven JAM tickets, generated proofs,
four-thread signing and native-boundary checks now also pass through the production library. Local
M2 migration regression parity is reached for the implemented release-reference scope; the
draft-text discrepancy, Ed25519 policy and Linux confirmation remain separate gates. Next: M3
nonblocking UDP/socket readiness and registration retirement. See the [cumulative
trial](nimony-trial.md).
