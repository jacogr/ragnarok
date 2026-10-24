# Bandersnatch Thin v1 primitive contract

The adopted Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` cites
**Draft 35**. The [qualification matrix](bandersnatch-thin-qualification.md)
resolves its suite, transcripts, encodings and exact references. Production uses
pristine ark-vrf 0.6.0 `dfb696dfb92425009af80dbbb403e647f6c9e3e4`, its
`bandersnatch` **v1** suite, and specification Draft 35
`122f52fb63c6e8eb887aa7416f869aba5075519b`. Draft 35 identifies vector generator
0.5.3 `9ec593e98b69395e97680330e75b5235b48121f4`. The chosen newer implementation
retains that executable profile while improving canonical decoding and API safety;
it was selected against vectors, not its version number.

## Maintained ABI and policy

| Primitive | Contract |
| --- | --- |
| Scalar import | Exactly 32 canonical little-endian bytes, nonzero scalar, never a seed |
| Public key | 32-byte compressed Edwards prime-subgroup encoding |
| Ordinary signature | `output(32) || R(32) || response(32)`, Thin, no serialized challenge |
| Verified output | First 32 bytes of v1 transcript-based output derivation |
| Ring proof | Output + Pedersen + membership, exactly 784 bytes |
| Ring commitment | Ordered normalized keys, 144 compressed bytes |
| Setup | Immutable opaque owner; explicit requested capacity 1..1023 and public SRS |

Nim owns raw context, separate additional data, protocol signing domains, exact
encodings, invalid-member substitution and retained ARC ownership. Rust owns only
primitive key/setup allocations and equations. Buffers are synchronously borrowed;
outputs are published only after complete success. The 65536-byte input/AD cap is
an adapter resource budget, not a JAM wire rule. Reason codes and owner ABI are
unchanged. All decoded composites undergo validity checks and canonical
re-serialization comparison; suffixes, off-curve/subgroup points and invalid scalars
fail. Verification exposes no output on failure.

Identity is a valid subgroup point during ring normalization and is never silently
replaced by padding. It is rejected as a public key, input, output or ring member
at the operation boundary. Thin R and Pedersen R/O_k may legally be identity.
Invalid encodings alone become the v1 padding point
`da5ca18e76fbd5467319795e26fd80f0b9cf7fc888d995348b7ff299197a42c4`.
Backend failures/panics remain typed failures and do not become padding.

## Ring and dependency provenance

The Draft 35 public Zcash Powers of Tau-derived uncompressed SRS has the unchanged
SHA-256 `1d7d27e4f5f3c6190989bea58803180d3e19f725a57069392a405ac78b233c7d`:
6145 G1 and two G2 points. Source checks precede embedding, and Rust validates
points before setup construction. No insecure SRS generator runs. PIOP domain is
`next_power_of_two(max(requested,1)+257)` for this scalar field; PCS needs
`3*domain+1` G1 powers. Capacities 6/8 use domain 512 and 1023 uses domain 2048.
Requested capacity, actual rounded capacity and member index are checked separately;
no backend index wrapping or member truncation is accepted by the ABI.

The lock moves arkworks 0.5 to 0.6, ark-transcript 0.0.3 to 0.0.6, ring-proof
0.0.6 to 0.0.10 and their required closure. Both primitive manifests record the
same reviewed lock hash. Enabled ark-vrf features remain explicit `std`,
`bandersnatch`, `ring`, `secret-split`. Default `RingSetup::from_pcs_params`
constructs a blinded context; neither `new_without_blinding` nor insecure setup
constructors are used. The backend's removal of a vector feature does not justify
using its public non-ZK context constructor. Locked/offline builds remain mandatory
following setup's permitted dependency fetch. Upstream trees remain pristine.

## Evidence and limits

Initial direct ABI qualification reproduces all seven Thin signatures byte for byte,
verifies all seven Draft 35 ring proofs and their exact ordered roots/outputs, and
generates/verifies a randomized production-feature ring proof. An independently
written Python affine/transcript reference reconstructs all seven Thin public keys,
outputs, nonce commitments, responses and output hashes using supplied H points.
Its extended test-only mathematical
oracle also reproduces all seven input points and complete signature/output bytes,
using the v1 XMD/Elligator2 equations. It never loads native code. This is a separate
implementation check, not an independent KZG membership or security audit.

The unchanged pinned historical JAM tiny/full tickets all fail the new ABI with
status 4 and leave sentinel output untouched. Their provenance remains checked;
those failures explicitly record profile incompatibility rather than current STF
success. Historical roots and transcripts must never trigger fallback to IETF.
The [archived release contract](bandersnatch-release-reference.md) preserves old
passes, nonce evidence and the separate draft-29 challenge discrepancy.

The vector source is advanced globally to gp-next
`23061ae1f9b51171c01387e7dde0f15794c98e24`, whose changelog and Safrole guide
explicitly select Draft 35/ark-vrf 0.6.0. All 379 existing consumed source paths
are rehashed. Reduced positive tiny/full tickets and the padding-root fixture are
regenerated from exact published fields; seven current tickets and the padding
root pass the checked contextual driver. The three original reduced files are
retained byte-for-byte under `vectors/historical/bandersnatch`, with original
hashes and an explicit cross-profile rejection check.

Consumer validation uses this aligned source and explicit authored positives;
incompatible historical fixtures retain their separate identity. The same
seven selected full trace pairs still contain 89-byte service metadata; independent
root verification succeeds, but expansion to 105 bytes changes roots and cannot
recover hashed logical identities. This specific complete-STF source limit does
not block stage vectors, signed-header chapter comparisons or authored current
schema end-to-end cases.

Draft 35's RFC9380 wording omits its 48-byte expansion prefix deviation; its vectors
and the selected v1 implementation agree. Later Draft 36 states the deviation
explicitly. The RFC-compliant 128-byte-prefix v2 is a different suite, not a silent
repair. This executable vector profile is not literal RFC equivalence, a security
audit, full published STF parity or a production-readiness claim.

## Current consumer results and published trace gate

Checked ARC/Clang native rotation, ticket admission, schedule and markers pass
against the advanced stage vectors. Authentication and complete Safrole component
publication pass three independently authored current Thin cases (two within an
epoch, one crossing), plus existing native authored ticket/fallback boundaries.
Expected credentials, entropy/time, markers and chapter bytes come from the Python
mathematical/byte/hash reference, never native STF observations. The input ring
constant is six copies of G under the qualified SRS/domain512; it is a valid input
fixture, not an independent ring-cryptography audit. These are six required global
chapters plus an unrelated sentinel, explicitly not a complete sixteen-chapter JAM state.

The advanced vector source's stage proofs are current, but its sampled signed
traces are mixed-profile. Exact witness `traces/fallback/00000001.json`, SHA-256
`d4c48b72483c0dda92d490d60d1fef1aab49dd50e0db87d3a3671129c0f38b52`, has
nonsquares in both Thin R positions (seal and entropy proof). Its entropy proof
is unchanged from the old corpus. Native authentication refuses all twenty
selected unchanged headers as `InvalidSeal`, with one seal attempt and no
verified output. The old source bytes/root expectations are never re-signed,
patched or relabelled as current positives. This is a concrete external signed
trace parity gate, separate from successful Thin migration and stage validation.

The current metadata audit separately re-verifies fourteen published map roots
and all twenty-six 89-byte metadata observations. Authored current-schema full
state/STF work proceeds independently; neither primitive/component success nor
test-only metadata expansion establishes published full STF parity.
