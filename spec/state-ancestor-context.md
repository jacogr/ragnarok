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

Dedicated source-owned rejection fixtures prevent external context/data access, result retagging,
partial payload extraction and demand/preparation forgery. Three independently executed native
runtime probes cover default capture, genuine constructor refusal and invalid-index extraction;
a real canonical-header positive control uses the same accessors successfully. These checks retain
exact diagnostic/exit predicates through the established guard and failure runners.

`prepareCandidateReports` exposes a distinct successful prefix owner after exact-parent block
transition and recent-report preparation, before accumulation execution. `candidateLookupDemand`
uses that original report binding. `completeCandidateReports` rechecks the original canonical view,
completes lookup admission under captured policies and only then executes/finalizes accumulation.
The existing one-shot API now composes the same two stages, preserving its public contract and exact hash work. A genuine guaranteed two-guest
fixture verifies missing/satisfied demand, failed completion without context, exact resulting root,
no early publication, two actual guest executions and refusal after canonical advancement.

Raw input discovery is explicitly enabled by `BlockInputLimits.discoverAncestors` (default false).
An incomplete certified demand returns `NeedsAncestors` and retains the exact generation/prepared
block in `AwaitingAncestors`; redundant raw bytes retire. Only after worker collection may the host
call `resumeAncestors`, which checks exact canonical identity and all count/byte/owner bounds before
replacing context. Refusal preserves suspension. A later preparation turn checks the supplied chain
and completes the original reports, without repeating block decoding/signatures. Partial context can
suspend again. Genuine tests cover completion, repeated missing context, stale IDs and atomic refusal.

The actual native preparation worker now has a dedicated discovery/resumption integration witness.
One worker collects `NeedsAncestors`, restores host access, refuses resubmission while the input is
awaiting context, then accepts the same generation after bounded resumption. An old first ticket
cannot collect the second lease. Late cancellation of discovery and late cancellation after real
guest execution both expose only `Cancelled`. Canonical state never advances in any worker stage.
One thousand success/cancellation cycles require equal live ARC occupancy after joined cleanup.

The framed `BlockDownload` owner now preserves `AwaitingAncestors` after collecting a real worker
demand. The plain `NeedsAncestors` status carries no execution prefix; a separate successful guarded
query retrieves the certified demand. Resumption checks the same generation and Services exclusion,
then makes only the original prepared input Ready. Typed quota refusal leaves suspension intact.
A real Services test verifies two managed leases, no second stream, restored host availability,
exact demand, atomic quota refusal and canonical publication only on a later handoff tick.

The scheduled session exposes demand/resumption only for its exact immutable attempt token,
without an active native stream or queued adoption. Resumption retains the original scheduler
reservation and input generation. Foreign/stale tokens, still-live streams and queued successors
cannot substitute context. A real TLS exchange plus two Services worker leases verifies stream
retirement, missing context, atomic quota refusal, later adoption and final token retirement.

Outgoing peer catalogs now support bounded `disconnectPeers` turns after all stream callbacks
retire. Draining disables readiness/reopening, sends actual QUIC connection closure, polls once
and destroys each endpoint only after its native live-connection count reaches zero. Exact ID/key
reservations survive. This is necessary before ancestry acquisition opens fresh endpoints against
a one-peer listener. Real two-listener tests cover pending-open refusal, complete stream close,
two graceful drain cycles, exact-pin reconnects and attempted identity replacement.

Dispatcher discovery now crosses explicit `DrainingAncestors` and `AwaitingAncestors` stages.
Collection ends the worker/RPC lease, graceful connection retirement ends all peer endpoints,
then the host may inspect the certified demand. Resumption preserves the original attempt and
its total deadline; expiration cannot create a new budget. A later tick submits the retained
prepared input, with the original request already consumed. Real TLS/worker/adoption tests prove
one child request, zero live child peers while awaiting context, atomic quota refusal, no early
publication and exact deadline refusal without canonical advancement.

`--download-discover-ancestors COUNT` opts into child-driven discovery with one whole-run allowance
of 1..64 headers. It is unique, canonical positive decimal, state-enabled and download-only, and
mutually exclusive with up-front `--download-remote-ancestors`. Local/file context may still be
supplied. Defaults and failed parses expose zero allowance; no option opens sockets by itself.
Parser tests cover every accepted count, malformed/duplicate/foreign-command controls, both
conflicting option orders and atomic reset. The activation field remains private.

The production command now enables discovery only from the explicit option. It reserves the entire
local/file + remote allowance + future-parent count before outgoing IO, receives each child once,
then acquires only a certified missing suffix after joined worker/connection retirement. Useful
request maximum is bounded by remaining whole-run headers and slot distance. Each nonempty valid
response subtracts its actual header count; short responses can resume and discover again without
re-decoding/re-authenticating the child. One shared command deadline and the original child attempt
deadline bound every acquisition. Resumed execution needs no child endpoint; successive children
reopen only the exact preserved peer identities. Existing up-front acquisition remains separate.

The command integration suite uses independent forked TLS responders to require child-before-
ancestor ordering and one original child request. It covers genuine guaranteed two-guest adoption,
already supplied context (zero ancestry requests), invalid child seal (zero ancestry requests),
empty/wrong-parent/suffixed/no-FIN/byte refusals, pin/count preflight, finite two-peer fallback and
real durable adoption/restart with complete-map/history/finality checks. Refused remote context
never reaches canonical publication.
