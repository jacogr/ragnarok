# Immutable state ancestor context

Scope: capture an immutable newest-first sequence of full sealed headers from a caller-selected
parent, then use it to support report lookup queries and bounded missing-context planning.
Gray Paper 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/reporting_assurance.tex` contextual report validity and C.2 sealed header serialization remain
unchanged. JAMNP-S requests continue to use the separately pinned CE128 contract.

The context is structural evidence linked to the supplied parent, not consensus authentication,
execution, canonical history, a complete-state map or a light-state proof. Failed/default results
contain only reasons and require success before extracting data. Limits include the parent.

`captureAncestorContext` preflights every owner and aggregate byte/count extent before hashing or
copying. It recaptures exact canonical headers under the current profile, hashes full seals with
BLAKE2b-256 and requires strict slot descent and every child-parent link. Read-only indexed access
retains immutable owners; no sequence backing escapes. A parent-only success differs from default.

Completion checks: `make unit SUITE=ancestor_context` and registration inventory. Authored independent
sealed chains cover skipped slots, order/duplicate/gap refusal, defaults, exact and exceeded quotas,
invalid indices and source-sequence replacement. Consumer migration and missing-context planning
remain later layers. M1 framing is complete; complete state serialization/JAM parity remain open.

`extendAncestorContext` appends an older suffix atomically, preserving the selected parent and
all prior context aliases. Count/host descriptor bounds precede allocation. Complete recapture
under the supplied current limits prevents a formerly permissive profile from bypassing a stricter
consumer. Empty extension revalidates; default context, bad link and late quota failures expose
no extended prefix. The focused suite checks these refusal and ownership boundaries.

`findLookupAnchor` returns a newest-first ordinal only after matching full sealed hash and lookup
slot and comparing the lookup posterior root with its retained child's prior-state commitment.
The selected parent itself lacks a retained newer child and cannot satisfy this proof. Missing
hash, wrong slot, absent child and wrong state have distinct typed refusals. The focused suite
covers each case and both valid child positions. No candidate header is used as the proof child.

Report lookup validation now retains the immutable context instead of a second header sequence.
`checkReportLookupAnchors` preserves its public input/result contract and exact refusal mapping:
wrong slot or absent proof child remains `MissingLookupAnchor`, and incorrect child commitment
remains `WrongLookupState`. Candidate-time ordering remains a report-stage check. Existing
signed projections, authored ancestry cases, all-owner preflight and later backend failure/ARC
witnesses run unchanged through the extracted implementation.
