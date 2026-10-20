# Final report-only accumulation candidate

## Scope and authority

Bind a completed stopped continuation/reentry to its actual final full-map service state and the
union of selected output pairs, replacing C(16) only on a private fork. Authority remains GP 0.8.0
revision `07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation.tex SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`, `accseq` n=0 and
`finalstateaccumulation`. Output ordering and its pins remain those of the
[retained output history](accumulation-reentry-outputs.md). No protocol pin or domain changes.

Accept only a genuine completed continuation or reentry whose source dispatch flag is false.
That source has no selected reports, allowances or transfers and its certified completion has
no service effects. Its retained prior map therefore already includes every earlier completed
batch exactly once. Do not replay any prior batch. A stopped suffix can retain unaffordable
reports; successful finalization does not claim that the original queue was exhausted.

## API and ownership
+
+The [shared successor contract](pvm-state-successor.md) also accepts the opaque
+`StoppedAccumulation` driver alternative, dispatching to those same finalizers.
+Read-only queue, authenticated admission and exact original-parent accessors keep
+state consumers independent of the execution graph's internal traversal shape.
+
`prepareFinalAccumulation` accepts a stopped `CompletedAccumulationContinuation` or
`CompletedAccumulationReentry` plus `AccumulationOutputHistoryLimits`. It refuses default sources
and unfinished dispatched rounds before collecting outputs or hashing. Output preparation retains
its own bounded round/outcome/pair policy and returns only the selected output reason on refusal.
C(16) is encoded freshly, the exact terminal prior is forked under its inherited store limits, and
one private atomic write replaces that chapter. Store/backend refusal returns only its guarded
reason; no candidate or partially collected source escapes. Callers' stores and all source snapshots
remain immutable on success and failure.

`PreparedFinalAccumulation` privately retains the output owner, completed full-map candidate and
copied observations. `finalAccumulationInfo` reports processed original-queue prefix, remaining
pending reports, actual remaining budget and output-history counts. `finalAccumulationOutputs`
retains exact initial/continuation/reentry provenance and supports existing explicit history-root
derivation. `finalAccumulationState` retains the complete candidate snapshot, including earlier
service/provision effects and the fresh C(16) log. Defaults are distinct from initialized empty
results, result payloads require selected success, and failure tags/reasons are read-only.

This is the supported report-only accumulation candidate, not an atomic whole-block transition.
History C(3), queue C(14)/C(15), statistics C(13), transfer-aware recursion, the remaining account/
privilege effect merger, preimage-stage ordering and block publication remain subsequent work.
PVM account-publication work remains independent. M1 framing is complete; full state serialization
and accumulation/block parity remain open.

## Completion tests

Use real signed multi-round executions and a genuine stopped completion. Reject live completed
rounds, default sources and short output-history policies. Check exact literal C(16) bytes, retained
source/map identity, copied observations, unchanged unrelated entries, inherited complete-map
roots, repeatability and detached lifetime. Exercise both continuation and repeated-reentry terminal
forms, including empty queues, unaffordable nonempty suffixes, present outputs and earlier real
provision changes. Inject a backend refusal during private C(16) publication, retain every prior
snapshot, retry successfully and check 1,000 ARC cycles. Add strict extraction/privacy/nominal
probes and run the new registered suite, source-owned inventory, affected Python tooling checks
and pinned formatting. Reuse unchanged collector/PVM/fixture consumer evidence.

## Local verification

Passed `make unit SUITE=accumulation_finalization`. Genuine first-continuation and repeated-entry
terminal sources cover empty queues, unaffordable nonempty suffixes and a four-report completed
prefix. Literal 145-byte four-pair C(16) replacement and one-byte empty insertion match expected
complete-map roots while every unrelated original entry remains unchanged. Live/default sources
refuse without hashing; short history policies preserve their guarded output reason. A failed
private map hash leaves all priors intact, retry succeeds, and earlier fulfilled provision state
survives without replay. Copied progress and detached source/candidate lifetimes pass.
The 1,000-cycle success/backend-refusal workload retained 825,744 occupied bytes before and after.

The signed reentry fixture gained optional extra authored parent entries for an existing-log
replacement witness. Its unchanged defaults remain covered by
`make unit SUITE=accumulation_reentry_cycle`: 914,944 occupied bytes before/after 1,000 cycles.
Eight strict runtime extraction probes and five privacy/nominal compiler rejections passed.
Python discovery passed 443 tests with seven skips; source-owned inventory, pinned formatting and
diff checks passed. Diagnostic builds reused existing native libraries; unchanged collector/PVM
checks and passed compiler guards were not repeated during probe-only corrections.

Evidence is retained under ignored `build/accumulation-finalization/`. These are local macOS
results, separate from exact-head Linux CI. Queue/statistics/history coordination and final block
publication remain open alongside the existing transfer/account/privilege gates. M1 framing
remains complete; full state serialization and accumulation parity remain open.

[Accumulation statistics](accumulation-statistics.md) now derive work-item counts and actual
service gas from this finalized history without writes; combining them with other C(13) activity
and updating account timestamps remain subsequent work.
