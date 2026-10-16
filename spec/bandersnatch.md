# Bandersnatch: GP 0.8.0 release-reference profile

Target: Gray Paper v0.8.0, release-designated ark-vrf 0.2.2 (draft-text discrepancy documented below),
`07f041dabd073f9018b418e9ee72e79dd2185401`,
[Bandersnatch appendix](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/bandersnatch.tex)
and [Safrole tickets](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/safrole.tex).
[All pins](bandersnatch-pins.json) include Rust, Nim, source-tree hashes,
Cargo.lock hash, SRS hash, published vectors and original/reduced JAM fixture
hashes. Sources and dependencies build without local patches.

## Suite choice is a compatibility requirement

The [draft-29 release](https://github.com/davxy/bandersnatch-vrf-spec/releases/tag/draft-29)
explicitly designates **ark-vrf 0.2.2** as its reference implementation. We pin its pristine
[release revision](https://github.com/davxy/ark-vrf/tree/1ebde144e68f17344e51c2d5ce8db217425ba0f3)
and [draft-29 specification/vector revision](https://github.com/davxy/bandersnatch-vrf-spec/tree/bce69d059124a2bec80898912413ffef1c4e4570).
This implementation uses `Bandersnatch_SHA-512_ELL2`, SHA-512, Elligator2, a 32-byte challenge,
canonical compressed prime-subgroup points and canonical little-endian scalars. Its IETF proof
bundle is output(32) || challenge(32) || response(32), matching GP's 96-byte signature contract.

Version 0.2.2 binds additional data into ordinary nonce generation and cross-binds both secrets
in Pedersen nonce generation. The adapter now uses the public scalar accessor; no upstream source
is patched. A Rust regression signs one VRF input under different additional data and requires
different recovered test-key nonces. The previous backend would reuse them. Published draft-29
ordinary signatures are reproduced byte-for-byte, and RingVRF/JAM 0.8.0 tickets verify.

The initially surveyed ark-vrf 0.6.0 is incompatible with this scheme. Its
`bandersnatch_v1` preserves the much newer 0.5.3 profile, not this original IETF
profile. Suite IDs, transcripts, points and challenge/proof formats differ.
Choosing Thin because its bundle also happens to be 96 bytes does not establish
compatibility. No silent suite/toolchain/protocol upgrade is made.

| Primitive | Wire/input/output contract |
| --- | --- |
| Scalar import | Exactly 32 canonical little-endian bytes, nonzero; explicitly a scalar, not a seed. |
| Public derivation/import | 32-byte compressed public encoding; import validates canonical prime-subgroup encoding. |
| Contextual signing | Borrow raw VRF input/context and separate additional data; own full 96-byte signature. |
| Contextual verification | Reconstruct input with hash-to-curve; verify proof; return only verified first 32 output-hash bytes. |
| Ring commitment | Ordered raw 32-byte members normalized in Nim; 144-byte compressed root. |
| Ring proving/verification | Complete output + Pedersen proof + ring membership proof totals 784 bytes; success yields verified 32-byte output. |
| Ring setup | Opaque immutable owner, requested capacity 1..1023; domain is backend next-power-of-two construction, using the pinned public SRS. |

Input/additional buffers are bounded to 65536 bytes per ABI call as an explicit
research resource budget. This is not a new JAM wire rule. Negative indices,
wrong widths, zero/excess capacities, too many ring members and nonmatching
key/index pairs fail before historical backend wrapping/truncation can occur.
Imports/verification never expose default output after failure. Signature/root
imports own exact-width encodings; full cryptographic decoding occurs during
verification.

## Invalid members and setup provenance

Only canonical/subgroup decode failures become the specified padding point:
`92ca79e61dd90c1573a8693f199bf6e1e86835cc715cdcf93f5ef222560023aa`.
The normalization loop belongs to each language. Backend panic/failure is
propagated, never hidden as padding. Ring order is preserved. The independent
JAM epoch-change padding fixture checks the resulting root.

The public Zcash Powers of Tau-derived 2^11 uncompressed SRS is taken from the
pinned specification assets: 6145 G1 and two G2 points. Its exact hash is checked
before compiling it into the Rust library. Rust validates the SRS points before
constructing each setup owner. No insecure seed-generated setup is exposed;
no trusted-setup generation script runs. Root/proof verification requires the
correct setup domain and SRS; the root bytes do not embed that configuration.
SRS provenance is recorded from the reference assets, not independently audited
ceremony transcript reconstruction. Full 1023-member and tiny six-member JAM
roots/tickets pass; tiny uses its explicit test-profile domain.

## Security and interpretation limits

The maintained bridge contains Rust unwinds with `catch_unwind` and keeps
`panic=unwind`; C status 6 becomes a reason-only backend-panic result. System
allocation exhaustion/abort, invalid forged pointers and owner lifetime races
cannot be contained this way. The public wrappers establish widths/owners for
normal use. Secret owners zeroize the retained scalar on drop. `secret-split`
is enabled for the backend's scalar-multiplication mitigation; unsafe
`test-vectors` (deterministic/non-ZK) features are explicitly forbidden by the
runner. Production-feature RingVRF proofs are generated and cross-verified.

The adapter rejects zero imported scalars and identity public/output points in
ordinary verification, identity ring members and identity ring outputs. These
are explicit research-profile guards around the historical backend, not a
complete audit or an assertion that the Gray Paper has resolved every exceptional
encoding/point rule. The guard does not substitute a valid identity point with
padding. Further audit/side-channel/canonicality review of this pinned backend and
its dependency closure remains an M2 gate. The release-reference migration preserves the existing wire scheme and introduces no upstream
source patches or project-owned cryptographic algorithm.

The published specification vectors share authors/provenance with the backend
and are not independent algorithm validation. Independent pinned official JAM
Safrole fixtures add external evidence for roots, ticket verification/output and
invalid-member padding, but do not exercise all client sealing domains or prove
full state-transition conformance. This remains a research integration, not a
production consensus backend selection.

## Remaining draft-text discrepancy

Draft 29 section 2.1 says `cLen = 16`, whereas its explicitly designated ark-vrf 0.2.2 reference
uses 32. The latter matches GP's 96-byte signature width, published draft-29 signature vectors
and published JAM 0.8.0 ticket verification. The draft's Appendix B also retains a stale-vector
warning, even though the checked ordinary vectors reproduce the release reference exactly.

We implement and test the explicit release-reference profile, including nonce updates. No
challenge padding, incompatible 80-byte signature or private compiler/dependency patch is added.
Exact agreement with the draft's literal 16-byte challenge statement remains blocked pending an
upstream clarification; `bandersnatch-pins.json` records both values, and `test_spec.py` reports one
focused pending text-consistency check. This discrepancy does not justify retaining the old nonce
implementation or claiming a full protocol/security audit. See [the migration audit](graypaper-0.8.0.md).

## Nimony owner/result migration

The pinned Nimony adapter preserves the release-reference ABI, 96/784-byte proof contracts,
normalization and source/SRS pins. Results hide discriminators/payloads behind read-only errors
and success preconditions. Key/setup ARC owners and their native handles express nullability
explicitly; stable retained locals protect defaults/closed handles. Close invalidates all aliases,
and final ARC release invokes the correct original Rust destructor once.

The test-only owner observer delegates real allocations/frees, counts live keys/setups across
scopes and injects constructor refusals without altering production/upstream code. Native tests
cover escaped scopes, retained aliases/replacement, close/final release, source/fixed copies,
capacity boundaries and recovery. It does not inspect freed memory or independently establish
scalar zeroization. The key/import workload returns live Nim occupancy 192 to 192 bytes after
1,000 warmed scopes; setup release is tested separately with the real SRS. Thirty-two isolated
result guards and seventeen privacy plus three nominal compiler probes pass. Three maintained
Rust bridge tests and the locked/offline Rust 1.99.0 build also pass.

The contextual fixture driver now also passes all seven ordinary vectors, seven ring vectors and
seven published JAM tickets, including exact bytes/outputs and wrong-domain rejections. One
generated ring proof and sixteen additional contextual messages pass. Four native workers each
complete 32 signing/verification rounds with independent owners and joined lifetimes. Native ABI
checks reject 99 ordinary widths, 785 ring widths and 64 mutated proofs without partial output.
The runner records 131 driver requests plus a separate failed-result contract probe.

These are local macOS ARM64 results under checked ARC/Clang LTO. Implemented release-reference M2
regression coverage now passes; Linux confirmation and the draft-text discrepancy remain separate.
M3 UDP/readiness and linked transport lifecycle checks now pass locally.
Shared identity/DER/framing validation now also passes locally.
CE 143 integration results and retained digest ownership now also pass locally.
The peer executable and one-shot authenticated CE 143 matrix now also pass locally.
Retained CE 143 service and integrated digest lifecycles now also pass locally.
Retained IPv6 mesh/reconnect and peer-loss recovery now also pass locally.
Next: same-process endpoint soak and remaining admission/resilience coverage. See the [cumulative
trial](../docs/nimony-trial.md).
