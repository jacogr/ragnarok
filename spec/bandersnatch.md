# Bandersnatch: pinned historical JAM profile

Baseline: Gray Paper v0.7.1,
`1c979cb59bb800f92ffff083a2701004dfc6cd33`,
[Bandersnatch appendix](https://github.com/gavofyork/graypaper/blob/1c979cb59bb800f92ffff083a2701004dfc6cd33/text/bandersnatch.tex)
and [Safrole tickets](https://github.com/gavofyork/graypaper/blob/1c979cb59bb800f92ffff083a2701004dfc6cd33/text/safrole.tex#L281).
[All pins](bandersnatch-pins.json) include Rust, Nim, source-tree hashes,
Cargo.lock hash, SRS hash, published vectors and original/reduced JAM fixture
hashes. Sources and dependencies build without local patches.

## Suite choice is a compatibility requirement

The contemporaneous
[specification](https://github.com/davxy/bandersnatch-vrf-spec/blob/38cf32d33d9d860feccd1f56b3bf6633c05669b0/specification.md)
uses `Bandersnatch_SHA-512_ELL2`, SHA-512, Elligator2, a 32-byte challenge,
canonical compressed prime-subgroup points and canonical little-endian scalars.
Its IETF proof bundle is output(32) || challenge(32) || response(32).
The corresponding pristine
[ark-vrf revision](https://github.com/davxy/ark-vrf/tree/29e53a0e642b1ccf95bdf881df5b0eaf3bbb8d04)
identifies itself as 0.1.0. It is selected as a historical research backend for
this pinned protocol, not as a recommendation to deploy old code.

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
padding. Further audit/side-channel/canonicality review of this old backend and
its dependency closure remains an M2 gate. Migrating safely to a maintained
backend preserving this exact historical scheme is also open; no upstream
source patches or new project cryptographic algorithm are introduced.

The published specification vectors share authors/provenance with the backend
and are not independent algorithm validation. Independent pinned official JAM
Safrole fixtures add external evidence for roots, ticket verification/output and
invalid-member padding, but do not exercise all client sealing domains or prove
full state-transition conformance. This remains a research integration, not a
production consensus backend selection.
