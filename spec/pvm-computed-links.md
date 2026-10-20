# Computed package-to-segment-root correspondence

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
work_packages_and_reports.tex, the existential package/root correspondence
constraint immediately after computereport; reporting_assurance.tex guarantorsig.
Vector pin remains `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume one ComputedGuaranteeTranscript and a stable borrowed list of
ComputedWorkReport witnesses. For each original canonical lookup entry, require
one completed witness whose computed original package hash and computed export
segment root both equal that entry. Retain the original transcript and all exact
witness owners only after the whole relation succeeds. No detached root map,
header, report bytes or replacement lookup is accepted.

Witnesses align with the source's canonical lookup ordinals. Exact shape rejects
missing or extra witnesses; no sorting, unused witness, duplicate-key collapse or
key-only fallback occurs. Repeated imports reuse their one unique lookup witness;
direct-root imports do not require a package correspondence witness. The original
computed report already enforces exact dictionary key coverage and canonical
ordering. At most eight entries fit fixed private storage. ElementLimit bounds
retained witness handles before inspecting witnesses or allocating an owner; it
is a local policy, not a protocol condition. Source and shape precede policy;
per-entry validation checks completion, package, then root. No hashing, wire
copying, proof verification or execution is repeated.

The owner proves only this computed correspondence. It does not recursively
certify a witness's own lookup, authenticate its execution state/anchor, establish
state/chain freshness, authorize signing, establish assignment/active population,
or certify availability distribution/assurance. The source transcript remains
usable without this owner; future signing admission must require the appropriate
completed gates rather than treating transcript construction as eligibility.

Completion coverage: genuine executed importer/exporter
sources and frozen independent singleton export root/report witnesses; empty,
repeated/direct imports and eight canonical keys; missing/extra/reordered/default
witnesses, correct root/wrong package and correct package/wrong root, late failure,
zero/exact/maximum policy; no new hashes under backend refusal; original source
retention, caller-list replacement, detached lifetime and 1000-cycle ARC release;
compiler privacy/nominal rejection and strict optimized result/accessor guards
with genuine positive controls.

Next: [exact execution-state binding](pvm-computed-state.md), then anchor provenance
before signing eligibility and guarantee publication. M1 framing is complete; full state
serialization and whole-block parity remain open.

Local evidence: checked optimized macOS ARM64 `make unit SUITE=pvm_computed_links`
passes the independent complete SingleReport wire witness and frozen singleton
export roots, genuine computed importers/exporters, eight strictly canonical keys,
repeated/direct imports, an explicitly initialized empty lookup, and exact/short/
maximum policy. Wrong-package witnesses with the correct root, wrong-root
lookups with the exact package and independently valid singleton inclusion,
missing/extra/default witnesses, late seven-entry-prefix failures and full-width
invalid ordinals all return their selected reasons. Caller list replacement,
original transcript/exporter retention, detached lifetime and zero new hashes
under backend refusal pass. Fresh 1000-cycle ARC occupancy is 1033280/1033280
bytes in the isolated warmed workload.

Eleven strict optimized result/accessor guards pass with genuine independent
exporter-wire and retained-correspondence controls. Seven compiler guards reject
private owner/tag/payload access and source, detached-map, policy and index-domain
substitutions. The pinned compiler prints the detached map's generic mismatch as
`[2] expected: openArray but got: seq`; the fixture requires that exact argument
position and constructor call. Formatted unit/driver semantic checks, inventory,
20 affected inventory/provenance tests and pinned formatting pass. Prior report,
export and transcript oracle evidence is reused with all 2971 prior source/build
inputs verified byte-identical. Full local logs, input identities and reuse proof
remain in ignored `build/computed-links-*` files. Exact-head Linux CI remains
separate; remote checks were not requested.
