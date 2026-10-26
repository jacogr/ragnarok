# JIP-5 validator keys

Scope: shared native key derivation and migration of the six-node Tiny devnet to the published
Alice, Bob, Carol, David, Eve and Fergie identities. JIP-5's exact domains and published vectors
are the acceptance authority. Current Gray Paper/Bandersnatch suite, dependencies and SRS stay pinned.

The adopted JIP-5 revision is [polkadot-fellows/JIPs #23](https://github.com/polkadot-fellows/JIPs/pull/23),
head `110b0f2f9accb90b3f7bf3c847942bc854f3ef75`, selected by the maintainer on 2026-10-26.
The exact normative text and vectors are [pinned here](https://github.com/polkadot-fellows/JIPs/blob/110b0f2f9accb90b3f7bf3c847942bc854f3ef75/JIP-5.md).
It explicitly selects Draft 35 A.3 and `Bandersnatch-SHA512-ELL2-v1`, matching the existing
ark-vrf 0.6 pin. Historical SHA-512/reduction-only derivation and its old public keys are not
accepted alternatives. Alice's current public key is
`4fc1cc2146c5463a023a66d1fc72829025ef654f1e1dd5c917c40346c2b3aa06`.

The 32-byte master seed is not prehashed. Development indices repeat their uint32 little-endian
encoding eight times. Domain ASCII bytes (without terminator) precede the master seed for a
32-byte BLAKE2b digest. Ed25519 imports that digest as its seed. Bandersnatch imports its digest
through the pinned suite's Draft 35 A.3 transcript procedure, including nonzero retry. The
current Draft 35 v1 signing/verifying profile and all dependency/SRS pins remain unchanged.

Protocol domain composition lives in `src/crypto/validator_keys.nim`, not the protocol-neutral
`src/lib`. Native ABI seed import owns only the suite's seed-to-key primitive. Master input remains caller
owned; scratch messages/digests are explicitly wiped and signing keys use existing opaque owners.
Ed25519 PKCS8 export is explicit, unencrypted and caller-owned. Only Tiny's development identity
command exports known public development secrets for TLS; the Python launcher does not reimplement
derivation. Genesis roster, block authors and peer certificates all use the same indices.

Completion checks: all six published development key pairs plus JIP-5's nontrivial seed; full-width
indices, bad lengths, domain separation, retained/cleared seed behavior, seed-vs-scalar distinction,
OpenSSL certificate consistency, Tiny authoring and the fourteen-block epoch/restart acceptance.
New identities change genesis, ring commitment, block hashes and state roots. Old devnet directories
remain tied to their original genesis and must not be reused as the new chain.

The historical telemetry interoperability fixture remains an attributed Polkajam export. It is
not regenerated with these new keys or used as Tiny's genesis/signing source. Existing ordinary
STF fixture keys likewise remain fixed; only the Tiny oracle supplies its explicit new public-key map.

## Verification

Local macOS ARM64 checked ARC evidence on 2026-10-26:

- `make unit SUITE=validator_keys`: all seven revised JIP-5 vector cases, exact-width refusals,
  secret scratch erasure, hash-backend failures, detached PKCS8 export and cleared aliases pass.
- `make unit SUITE=crypto_seeds` and `make unit SUITE=bandersnatch_owners`: existing ownership
  suites pass, including their 1,000-cycle allocation-baseline observations.
- `make unit SUITE=tiny_block_author`: all six new keys author through fourteen validated blocks,
  with wrong-key, bad-seal, stale/replayed-parent and unchanged-parent controls.
- Both registered failure-only constructors reject success fabrication at their contracts.
- Five Rust adapter tests, seventeen focused Python reference/harness tests, all 448 production
  modules, inventory and pinned formatting pass. Historical epoch/Thin fixture expectations remain unchanged.
- `make check-devnet`: six nodes, fourteen slots, epoch crossing and stopped-node restart/catch-up;
  all six identities author. The independent reference matches 90 complete maps and 84 signed journals.

Live evidence: `build/tiny-devnet/check-20261026-165719/result.json` and its pre-launch `independent/plan.json`.
Final block hash `adfda72589ac365298253c1621b6d9bf0459da0136dc7a159a1efd1f8a8e187f`;
complete state root `7d5a0390d424e52450a20ab6fb78007f2589ec54ffb2c7075b9bb3ac9e612a6f`.
This is local evidence; exact-head Linux CI remains separate. The genesis ring commitment remains
an attributed native cryptographic input, not an independent Ring/KZG calculation.
