# Complete work reports and guarantee-message workload

Normative source: Gray Paper v0.7.1 commit
`1c979cb59bb800f92ffff083a2701004dfc6cd33`, Appendix C.1/C.2 and
`text/reporting_assurance.tex` equations `workreport`, `limitreportdeps`,
`limitworkreportsize`, and `guarantorsig`. Fixture revision and content hashes are in
[pins.json](pins.json). Upstream sources remain unmodified.

Wire order: availability (package hash, E4 bundle length, erasure root, segment root,
E2 segment count); context (four hashes, E4 lookup slot, natural prerequisite count,
ordered prerequisite hashes); natural core index; authorizer hash; natural authorization
gas; natural authorization-output length and bytes; natural lookup count and ordered
hash/root pairs; natural digest count and complete work digests.

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

Acceptance includes independent encoding/field decoding, both official parameter sets,
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
