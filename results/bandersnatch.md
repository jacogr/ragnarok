# M2 Bandersnatch research integration

Observed 2026-10-14 on macOS 27.0.1 arm64. Both languages now expose typed
contextual signing/verification, ordered ring commitments, anonymous proving/
verification and verified 32-byte output extraction through one small maintained
Rust/C ABI. Native domains and invalid-member padding policy remain in Nim/Odin.
Backend sources are pristine: no upstream patches were added.

## Compatibility established for the pinned cases

GP v0.7.1 uses the original `Bandersnatch_SHA-512_ELL2` IETF profile. The newest
ark-vrf 0.6.0 and its compatibility `bandersnatch_v1` profile are different
schemes; its v1 preserves 0.5.3, not the original GP scheme. The reference spec
and ark-vrf revisions contemporaneous with the July 2025 Gray Paper were checked
against public specification vectors and independent official GP v0.7.1 cases.

The historical pristine backend at
`29e53a0e642b1ccf95bdf881df5b0eaf3bbb8d04` identifies as 0.1.0 and reproduces:

- All seven published IETF vectors: exact public keys, 96-byte signatures and
  the first 32 output-hash bytes.
- All seven published RingVRF vectors: 144-byte roots, successful 784-byte proof
  verification and exact 32-byte outputs.
- Seven independent official JAM tickets: three tiny and four full. The
  verified outputs equal the official posterior accumulator ticket identifiers;
  the reconstructed six- and 1023-member roots equal the official roots.
- The official tiny epoch-change padding root, including invalid member
  substitution with the specification's exact padding point.

This establishes concrete compatibility evidence, not complete JAM conformance
or a production backend endorsement. See [the pinned interpretation](../spec/bandersnatch.md)
and [source/SRS/toolchain/dependency/fixture pins](../spec/bandersnatch-pins.json).
The original full STF files are downloaded and hash checked in ignored build
storage; committed fixtures retain only relevant crypto inputs/expected outputs,
and the runner verifies their reduction against the originals.

## Observed validation

Commands:

```sh
python3 tools/format.py
python3 tools/format.py --check
cargo fmt --manifest-path native/bandersnatch/Cargo.toml -- --check
python3 interoperability/test_bandersnatch.py --fetch
```

All four suites pass: Nim ARC debug/release and Odin vet/strict-style debug/
optimized, linked to the same optimized Rust library. Each runs the published
and official cases above, wrong widths/scalars/points, context/additional-data
mutations, owner/default failures, incorrect membership indices/keys and
excess-member rejection. Nim tests input mutation, retained scope and alias
invalidation; Odin tests original-allocator single release and nilled handles.
These are ownership-behavior tests, not complete Rust heap-leak instrumentation.

Each native suite also passes four same-process worker threads with 32 rounds
of contextual signing/verification per independent scalar owner. Failed-result
payload selection traps in both debug and optimized builds. Six negative
compilation probes, preceded by positive import controls, reject public-key/
output and key/setup role mixing and private-owner-field access.

Cross-language tests pass 16 additional scalar/context/additional-data cases
with identical public keys/signatures/output hashes, plus two newly generated
production-feature anonymous proofs: one generated through Nim and verified
through Odin, and the reverse. These fresh proofs need not equal published
non-ZK deterministic ring encodings. The runner explicitly rejects any enabled
upstream `test-vectors` feature; `secret-split` is enabled.

Direct Rust/C ABI checks pass all 99 tested wrong ordinary widths and 785 wrong
anonymous-proof widths before borrowing proof bytes. Sixty-four deterministic
bit-mutated anonymous proofs reject without a caught backend panic or modified
output destination. Null/nonempty scalar input preserves the original out-handle;
oversized context fails before slice construction. Rust unit tests pass explicit
panic containment and canonical suffix rejection. Logs retain dependency
warnings without modifying old source to suppress them.

Rust/Cargo 1.99.0 and rustfmt are pinned to the installed local toolchain. The
official 2026-10-01 distribution manifest was checked and confirms Linux x86-64
availability. Registry versions/checksums are locked in Cargo.lock; source tree,
SRS, lock and fixture hashes are checked before compilation. Registry/source
fetches are explicit; subsequent builds/tests use `--locked --offline`.

Linux CI now installs that pinned official Rust toolchain and runs the new
Bandersnatch suite after ordinary crypto, before QUIC. It retains explicit
build/features/type-check logs and results only. The new Linux step awaits a
pushed run; this report claims local results only. Machine-readable results and
logs are in ignored `build/bandersnatch`.

## Remaining M2 gates

The older compatible backend needs audit/side-channel and exceptional-point/
canonicality review before production selection. The adapter's explicit identity
and index/capacity guards are not a replacement for that work. An audited,
maintained backend preserving the original scheme remains a migration question;
substituting modern Tiny/Thin/v1/v2 profiles would change the protocol.

The public SRS is the exact reference asset attributed to the Zcash ceremony,
not a new locally generated trapdoor. Independent ceremony/transcript provenance
review is still needed. Rust unwinds are contained; system OOM aborts, forged
native pointers and lifetime races are not recoverable ABI errors. Complete
secret-temporary erasure and allocator instrumentation are not claimed.

More client-specific sealing/domain integration, complete Safrole transitions,
the earlier Ed25519 acceptance-policy difference and BEEFY/BLS remain open.
No winning client language or completed M2 milestone is declared. API/lifetime
and reproducible build details are in [the adapter guide](../docs/bandersnatch.md).
