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

`planReportLookupDemand` accepts only a recent/age-certified report owner and a validated context.
It checks every existing lookup proof before publishing a missing-context plan. Missing hashes
strictly older than the retained tail may request extension; equal/newer slots, wrong slots,
missing newer proof children and wrong roots cannot be repaired by an older suffix and refuse.
The plan retains its original certificates. Its next child is always the context tail; useful
request count is capped by strict slot distance to the oldest missing lookup and explicit remaining
header allowance. No numeric distance is treated as a required chain length: skipped slots remain
valid. Complete plans require no request; zero remaining allowance refuses incomplete plans.
Focused signed/authored tests cover complete/missing/default/permanent-refusal and quota cases.

Report admission now has explicit `prepareBlockReports` and `completeBlockReports` boundaries.
Preparation owns the actual successful block transition, verified credentials, parent policy,
corrected recent history and exact policies. It certifies no lookup, assignment or final state.
Completion accepts only that opaque preparation plus older headers and performs lookup/package/
capacity checks. The original `planBlockReports` composes both and preserves nested refusal causes.
Existing signed composition and ARC tests run through that wrapper; explicit preparation/completion
positive and default negative controls cover the new boundary.

`planPreparedReportLookupDemand` binds the query to the prepared block's actual admitted parent
and captured limits. Callers cannot substitute a parent, slot, policy certificate or history.
All older inputs undergo complete structural capture. Defaults and broken supplied context refuse;
missing and satisfied signed report batches return explicit plans. Existing admission tests verify
two genuine reports need one older linked header and become complete with that exact suffix.

Demand admission additionally checks package uniqueness/dependencies and post-assurance core
capacity before authorizing any missing-header plan. These state-only failures cannot be repaired
by ancestry acquisition and therefore must not spend network attempts. The ordinary full planner
retains its original failure ordering. Signed duplicate-package, missing-parent-queue and occupied
core cases verify exact refusal with the entire older suffix absent; no discovery plan escapes.
