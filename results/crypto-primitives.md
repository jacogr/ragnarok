# M2 first primitive slice

Observed 2026-10-14 on macOS 27.0.1 arm64. Blake2b-256, ordinary Ed25519 and
legacy Keccak-256 are implemented in both languages with nominal hash/key/
signature types, checked payload-free failures and opaque retained seed owners.
Odin uses compiler-pinned core crypto; Nim uses existing pinned BoringSSL plus
a new pristine Keccak-team XKCP source tree behind a maintained C bridge.
No third-party source patches were added. Full pins are in
[crypto-pins.json](../spec/crypto-pins.json).

## Observed checks

Commands:

```sh
python3 tools/format.py
python3 tools/format.py --check
python3 interoperability/test_crypto.py --fetch
```

The crypto runner passes for Nim ARC debug/release and Odin vetted strict-style
debug/optimized builds. Each of the four suites passes:

- All five RFC 8032 section 7.1 public-key/signature vectors, covering empty,
  one-byte, two-byte, 1023-byte and 64-byte messages, plus signature/message
  mutations.
- All 151 pinned Wycheproof cases: 88 valid accepted, 63 invalid rejected. Twelve
  invalid cases fail exact-width signature import before entering verification.
- 56 message cases per hash, including empty/`abc`, 128-byte Blake2b and 136-byte
  Keccak boundaries, multiple blocks, deterministic random messages and 16 KiB
  input. Blake2b matches independent Python hashlib configured for 32 bytes;
  Keccak matches the test-only integer oracle anchored by published empty/abc
  results, with no SHA3 substitution.
- Default/cleared seed failures, input mutation after seed import, alias
  invalidation and exact seed/public/signature sizes. Nim retains an ARC seed
  after its import scope ends. Odin checks allocator refusal and 256 repeated
  imports/releases, returning tracked allocation bytes to zero each iteration.
- Four same-process native worker threads, each running 128 rounds of signing,
  verification and both hashes with independent retained owners/contexts.
- Failed-result payload selection traps in debug and optimized builds.

Thirty-two additional deterministic seed/message pairs produce identical public
keys and signatures, and each language accepts the other's signatures. Six
negative compilation probes reject hash/hash, hash/key and private-seed-field
misuse. Positive compilation controls verify that these probes reach valid
imports/types; diagnostics show the intended errors. Direct C ABI checks cover
null/nonempty inputs, unchanged outputs on argument failure and explicit wipe.

Logs and machine-readable summaries live under ignored `build/crypto`:
`build.log`, `type-checks.log` and `results.json`. Linux CI now runs this suite
before QUIC, reusing the same BoringSSL source/build. The new crypto CI step
awaits a pushed run; this report does not claim a Linux result.

## A verified acceptance-policy difference

Beyond the Wycheproof corpus, explicit probes use A=identity, R=identity and
S=0 over empty and `abc` messages. Pinned BoringSSL accepts both; Odin's default
rejects both because it rejects small-order A. Both reject the tested all-zero
A/R, S=0 case and S equal to the group order. The tests record these actual
provider verdicts and will expose a change on upgrade. No option was silently
tuned to make providers agree.

This is an unresolved JAM verifier policy gate, not a discrepancy in ordinary
key derivation/signing. The Gray Paper/RFC interpretation and further exceptional
point evidence must settle the consensus rule before a validator uses this
primitive verifier. See [the pinned contract](../spec/crypto.md). Test success
does not certify audit coverage, side-channel resistance or production secret
handling. Keystore/entropy/domain/codec integration and packaging remain later
work; current binaries/library are build-tree test artifacts.

The first three primitives are integrated and locally tested. M2 remains open
for the Ed25519 policy gate, backend audit assessment, Bandersnatch contextual
VRF/Ring-VRF compatibility and Rust/C ABI work, and BEEFY/BLS. Bandersnatch is
the next bounded round; no Rust backend has been selected by this change.
