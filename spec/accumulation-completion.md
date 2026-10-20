# Complete a stopped accumulation candidate

## Scope and authority

Connect the genuine stopped driver result to existing report-only finalization and complete
chapter composition. Authority remains GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401` and the pinned contracts in
[finalization](accumulation-finalization.md), [consensus composition](accumulation-consensus.md),
and [the driver](accumulation-driver.md). No equations, domains, codecs, pins or underlying
transition algorithms change.

## Contract
+
+The [shared successor boundary](pvm-state-successor.md) makes
+`prepareAccumulationComposition(PreparedFinalAccumulation, AccumulationCompositionLimits)`
+the canonical state-only entry. `AccumulationCompletionLimits` groups execution
+`finalization` and state `composition` policies. The stopped convenience entry
+finalizes once on the execution side and delegates to the same state implementation.
+
`prepareStoppedAccumulation` accepts only StoppedAccumulation and
AccumulationCompletionLimits. Select the existing continuation/reentry finalization overload
using the stopped kind. Run, in order, output finalization, accumulated history, ready queues,
recent history, account timestamps/statistics, validator observations, combined activity,
original-parent admitted preimage integration, authorization and fixed consensus/report chapter
composition. Resource policies remain separate for each existing phase. No caller can replace
parent/posterior maps, authenticated slot, entropy, observations, report assignments or entries.

Return the existing PreparedAccumulationConsensus on complete success, preserving compatibility
with exact-parent guarded publication. All source and state provenance remains in the existing
acyclic immutable graph. Refuse default stopped sources before any phase. A phase refusal retains
only its actual failed result, with guarded nested codec/transition/store reasons, never an
earlier successful candidate or partially composed map. Every intermediate fork stays private.
Success and failure leave caller handles, original snapshots and the stopped owner unchanged.
Do not replay guests, report admission, signatures or earlier history. Publication remains a
separate operation and retains its inherited exact-parent/version and write-policy checks.

This is bounded orchestration of the supported report-only path, not removal of transfer/account/
privilege gates, full block validation, persistent commits or light-node partial-state execution.

## Completion tests

Compare complete roots and retained source observations with existing independently constructed
manual phase chains for real signed empty, incoming/available, lookup/provide, epoch, culprit and
ticket fixtures. Cover both stopped kinds, repeated histories and yield output unions through
the actual driver. Exercise downstream exact-parent publication compatibility without new hashing
or candidate reconstruction. Refuse every phase's short policy and default sources; preserve
nested failure reasons, including a late seven-write composition refusal under inherited six-write
policy and backend failure after earlier phases complete. Prove unchanged original/stopped owners,
detached candidate lifetime and 1,000 ARC success/late-refusal cycles. Require strict extraction,
privacy/source-type compiler guards, source-owned fixture metadata, Python/inventory and pinned
formatting checks.

## Remaining work

Next bounded work joins initial execution, bounded driving and candidate completion into one
source-bound report-only preparation entry point. Publication stays separately guarded. Remaining
transfer/account/privilege integration, full block validation and full JAM parity remain open.
M1 framing is complete; full state serialization and accumulation/block parity remain open.

## Local verification

Passed `make unit SUITE=accumulation_completion`. Real signed empty, incoming guarantees,
combined newly-available/lookup/provide, culprit, ticket and epoch-transition fixtures match the
complete roots of independently built existing manual candidates. Reentry-backed seven-report
histories and real yielded output unions match an explicit manual phase chain. Both stopped kinds
retain the correct source graph; candidates outlive local fixtures and driver handles.

Each configured phase has a selected short-policy refusal, preserving its exact typed parent and
nested output/statistics/store causes. The six-write inherited store policy reaches final consensus
composition and refuses its seven-write batch with StateStoreError.LimitExceeded. A counted
backend refusal after successful manual-equivalent earlier work reaches the final overlay and
preserves StateStoreError.BackendFailure. Original parent owner identity remains unchanged.

Every successful tested candidate feeds existing exact-parent publication on a separately forked
test handle. It adopts the exact candidate snapshot while hashing is refused, with zero Blake2b
calls. Production completion itself does not publish any handle. The final 1,000-cycle workload
prepares successful combined candidates and late inherited-policy refusals, retaining 3,224,688
occupied bytes before and after.

Twelve strict runtime extraction guards and eight compiler privacy/stopped-source rejections pass.
Python discovery passed 451 tests with seven skips. Inventory passed 124 failure families, 1,782
probes and 189 native suites; pinned formatting and diff checks pass. Underlying transition,
codec, publication and unsupported-effect algorithms are unchanged; their existing literal
root/entry, vector and rejection evidence is reused. Logs remain under ignored
`build/accumulation-completion/`. These are local macOS checks, separate from exact-head Linux CI
and full JAM/STF parity.
