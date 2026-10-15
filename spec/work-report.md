# Complete work reports and guarantee-message workload

Normative source: Gray Paper v0.8.0 commit
`07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix C.1/C.2 and
`text/reporting_assurance.tex` equations `workreport`, `limitreportdeps`,
`limitworkreportsize`, and `guarantorsig`. Fixture revision and content hashes are in
[pins.json](pins.json). Upstream sources remain unmodified.

Wire order: availability (package hash, E4 bundle length, erasure root, E2 erasure-shard
count, segment root, E2 segment count); context (anchor hash, E4 anchor slot, anchor state root,
accumulation root, lookup-anchor hash, E4 lookup slot, lookup-anchor state root, natural prerequisite
count, ordered prerequisite hashes); natural core index; authorizer hash; natural authorization
gas; natural authorization-output length and bytes; natural lookup count and ordered hash/root
pairs; natural digest count and complete work digests. The fixed availability/context prefix is
272 bytes, up from 234 in 0.7.1. The three new fields have nominal types; a lookup state root cannot
be confused with an anchor state root, nor can the two timeslot roles be interchanged.

The erasure-shard count is a multiple of three from 6 through 1023, bounded further by three times
the caller's configured core ceiling. Equality with the actual active validator set remains a
state-dependent guarantee check outside this codec. All header-domain checks complete before any
encoder write, including when an invalid count is supplied through the public typed API.

The lookup has one count discriminator, consistent with the pinned official bytes;
C.1 dictionary ordering and C.2 variable-field notation describe that same sequence.
Hash keys and prerequisites use strictly increasing lexicographic byte order. Duplicate
or descending keys are noncanonical. Encoders require canonical input rather than silently
sorting caller data. The core index is a general natural, not E2.

Report limits: 1–16 digests; at most 8 prerequisites plus lookup entries; authorization
output plus successful digest outputs at most 49,152 bytes. Core count is explicit chain
configuration (2 tiny, 341 full), not inferred from serialized data. Codecs check these
structural limits, not state-dependent gas availability, roots, assignments or authorization.
Counts are checked before narrowing/indexing; fixed metadata arrays bound borrowed
parsing without input-derived allocation. Successful blob spans borrow the original whole
input/pool. Input must remain alive and stable throughout each borrowed call.

Encoding validates every source field, span, nested digest, aggregate payload limit,
capacity and whole-pool overlap before any output write. Failed results contain only a
reason. Owned snapshots privately retain the validated consumed prefix and metadata;
only scalar metadata and copies of owner-bound payloads or complete wire leave the owner.
Nim retains private acyclic snapshot storage through ARC.

The composed workload hashes canonical complete report bytes with Blake2b-256 and verifies
ordinary Ed25519 over the ASCII `$jam_guarantee` concatenated with that hash. The guarantee
timeslot is not part of this signing message. Verification measures the existing backend
verdict; it does not establish validator assignments or state eligibility. The documented
small-order Ed25519 acceptance-policy difference remains unresolved. Authored ordinary-key
fixtures must not conceal that gate or be described as independent published signatures.

Acceptance includes independent encoding/field decoding, both published 0.8.0 fixture profiles,
all truncations of representative reports, count/canonicality/ordering/aggregate limits,
late encoder failures and overlap atomicity, retained ownership under caller mutation,
and deterministic malformed-input fuzzing. Performance is separate from conformance.
Nim measurements use checked ARC/Clang LTO exclusively, as requested by the maintainer.


Profile correction (assurances follow-up): the pinned vector README specifies 2 tiny cores and
6 tiny validators. The standalone `codec/tiny/work_report` sample nevertheless uses core index 3;
it is a structural codec fixture, not a chain-eligible tiny report. The report harness exercises
its bytes with a permissive 341-core bound and separately requires rejection under the actual
2-core tiny bound. The earlier report's six-core profile label was incorrect; native caller-bound
range checking is unchanged. The tagged selection release preserves the earlier profile-label investigation.

Published v0.8.0 JSON/binary pairs come from `davxy/jam-test-vectors`, tag v0.8.0 at
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Their exact hashes are recorded in `pins.json`.
Tests independently construct the full wire from named JSON fields and observe every native
header field. Authored new-field boundary and legacy-layout negative cases supplement these
published vectors. See [the migration audit](graypaper-0.8.0.md).
