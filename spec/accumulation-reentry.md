# Accumulation reentry

Current transfer support is specified in [transfer-aware reentry](pvm-transfer-reentry.md).
It replaces the outgoing-transfer gate below with bounded canonical collection, paid-gas
restoration and combined transfer/report inputs for first and repeated rounds. The
report-only implementation and verification record below is historical; queue, depth,
state ownership and stopped-source contracts remain applicable.

## Scope and authority

Prepare the next report-only accseq entry after a certified completed continuation. Authority
remains GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation.tex
SHA-256 `bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`
(`accseq`, `accone`, `fnprovide`), pvm_invocations.tex SHA-256
`67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb` (actual gas collapse).
Pins, domains and the parked request namespace question do not change.

Advance the original queue offset by the completed continuation's selected count and subtract its
verified actual gas from its retained input budget. Prove bounds before arithmetic or narrowing.
Select whole pending reports in order with independent outcome/report/digest inspection limits,
including rejected reports. Reject outgoing transfers until transfer-aware recursion is integrated.
A stopped source cannot restart or rescan its blocked suffix. Preserve the immutable original queue;
no report reconstruction, old payload replay or repeated free allowances is permitted.

Preflight only the selected range's operands and report-only service groups. Then privately apply
only the just-completed later batch to its exact retained prior, inheriting complete-map store
limits. Return source, copied selection facts, report handles, inputs and actual successor only
after complete success. Failed/default results contain selected reasons alone. Service resolution
uses only these retained inputs/state and the authenticated slot. No caller state is published.

This layer prepares reentry; subsequent bound invocation, repeated completion/scheduling, output
union, transfer-aware recursion and final publication remain separate. PVM host implementations and
selected-account compatibility gates remain unchanged. M1 framing is complete; full serialization
and accumulation/block parity remain open.

## Completion tests

Use signed multi-report sources with actual initial and later guest executions. Distinguish actual
later gas from declared reservations; verify accumulated offsets, selected C.2 payloads, no old
operands/allowances, whole-report rollback, no bypass, zero-gas tails and full-width bounds.
Check stopped/empty/all-skip sources, independent short inspection/materialization budgets and
hash-free preflight. Use real initial OOG followed by later provision execution so only reentry
fulfills requests; compare independently authored full-map roots and literal histories, inject late
backend refusal and verify unchanged caller state/retry. Check exact source/state/input identities,
authenticated service slot, detached lifetimes, copied observations, strict guards/privacy/nominal
rejections, 1,000 ARC cycles, selected native/Python/inventory checks and pinned formatting.

## API and ownership

`prepareAccumulationReentry` accepts the completed later-round certificate and independent selection/
operand/input limits. It obtains the original queue and exact prior through that source alone.
`previous <= count` and `selected <= count - previous` prove the cumulative offset addition and
native conversion. `actual <= budget` proves subtraction. Candidate digest gas is subtracted from
a temporary remainder and committed only when its whole report fits. An unaffordable head blocks
all later reports, including zero-gas rows; a source with no dispatch does no suffix traversal.
Outgoing transfers are refused before materialization or state application.

The range uses the owning operand adapter's nominal start/count and retains original C.2 order.
Empty transfer/allowance arrays create only report-derived groups. Preparation then forks the exact
completed continuation prior and applies only that completion's batch; neither initial nor earlier
batches are replayed. Independent materialization refusals precede fulfillment hashes. A batch
refusal retains only the genuinely failed parent's reason alternatives, preserving nested contracts
while releasing prepared inputs and private state candidates.

`AccumulationReentryInfo` documents cumulative processed reports and the actual recursive budget,
separately from initial-entry facts. `reentryInfo` copies it; `reentrySource`, `reentryInputs` and
`reentryState` retain immutable owners. `reentryReportAt` checks the full-width nominal local
ordinal before adding its proven original offset. `prepareReentryAccumulationService` derives only
from the retained inputs, actual successor and authenticated slot, with guarded `serviceError`.
The private source graph is acyclic, and no accessor exports mutable snapshot storage.

## Local verification

Passed `make unit SUITE=accumulation_reentry`. A signed four-report queue consumes one report
initially, one in the certified later round and then selects only reports 66/67. The reentry budget
is 200,912 (200,956 input minus 44 actual gas), rather than subtracting the 200,000 declared report
reservation. Only two newly selected operands and 1,000 declared gas reach service 42; allowance-only
service 99 does not recur. Exact two-report/two-digest selection caps pass; short outcome/report/
digest and operand/input caps refuse independently. Full-width ordinals, copied observations,
retained lifetimes, zero-gas tails, whole-report rollback for `5 + high(uint64)` and no bypass pass.
Stopped sources retain their pending suffix without inspecting it under zero work caps. Empty and
all-skip sources preserve zero actual gas and initialized-empty semantics.

A real initial OOG has insufficient gas to reach provide; the later invocation does provide. Thus
reentry privately fulfills two still-outstanding requests at authenticated slot 2. Its successor
matches an independently authored complete-map root with literal `[1, 2, 0, 0, 0]` histories and
explicit preimage rows. The source retains `[0]` request history. Injected fulfillment hash refusal
preserves the exact original map and exposes nested `BackendFailure`; retry succeeds. Service
resolution matches only the actual successor/input owner, and the no-op/preflight cases perform
no hashes. The 1,000-cycle changed-map success/late-refusal ARC workload retained 1,028,336 occupied
bytes before and after.

Eleven strict runtime extraction guards and six privacy/nominal compiler rejections passed. Python
discovery passed 441 tests with six skips; inventory passed with 105 failure families, 1,572
data-driven probes and 149 native suites. Pinned formatting and diff checks pass. The new native
suite reuses the checksum-verified static report fixture, with no generated-corpus setup or runner
behavior change. Diagnostic iterations reuse prepared native libraries, and prior results for
unchanged owning implementations remain applicable. Logs are under `build/accumulation-reentry/`.

These are local macOS checks, separate from exact-head Linux CI. The new PVM eject work was inspected;
hosts and selected-account compatibility gates are unchanged. Next work binds invocation/completion
to reentry before repeated recursion and final output union/publication. Transfer-aware recursion
remains gated. M1 framing is complete; full state serialization and accumulation/block parity remain
open.
