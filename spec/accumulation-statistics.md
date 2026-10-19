# Accumulation statistics from finalized report-only execution

## Scope and authority

Derive the accumulation statistics mapping S(s)=(N(s),T(s),G(s)) from a genuine
`PreparedFinalAccumulation`. Authority remains GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation.tex SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`,
`accumulationstatisticsdef`. N counts every work-digest in the processed original report prefix,
including services whose code could not execute. G sums actual certified service gas across initial,
continuation and repeated reentry rounds, including allowance-only executions. For the supported
report-only finalization T is zero: the source's continuation gates already excluded outgoing
transfers and no transfer inputs were introduced. Omit exactly the all-zero tuples, not zero-gas
services which accumulated work-items. Order the resulting dictionary by numeric service.

## API and ownership

`prepareAccumulationStatistics` accepts the finalization certificate and independent local limits
for completed rounds, inspected gas rows (including skips and zero-gas rows), processed reports,
work-digests and retained nonzero services. Derive both report provenance and all round completions
through that exact finalization's output owner; callers cannot substitute rows, reports or gas.
Bounds precede descriptor/candidate allocation. Candidate storage is bounded by gas rows plus
work-digests, with native extent proofs. Sort candidates and combine by service in O(R + C log C) time
and O(R + C) scratch for R rounds and C candidate rows. Prove actual gas sums against the initial budget minus terminal remaining gas;
per-service sums are nonnegative subsets of that checked total. Work-item sums are bounded by the
preflighted digest count. Full-width local ceilings never become unchecked allocation sizes.

`PreparedAccumulationStatistics` retains the exact finalization and independent fixed service
records. `statisticsInfo` copies traversal/cardinality and actual gas observations;
`statisticsSource` retains the exact final state/output provenance; `statisticsAt` checks the nominal
`StatisticsServiceIndex` before narrowing and copies one `ServiceStatisticsEntry`. These records
contain only the accumulation delta in `AccumulationCount`, `TransferCount` and `accumulationGas`;
other fields are zero. They are not complete C(13) records or replacements for refinement/provision
activity. Defaults and refusals carry only reasons and extraction requires selected success.
No guest execution, hashing, account timestamp update or state publication occurs.

## Completion tests

Use actual signed initial/continuation/reentry executions and stopped finalization. Check literal
per-service work-item and actual gas totals, repeated services across rounds, allowance-only gas,
missing-code work-item counts, zero-tuple omission, pending suffix exclusion, numeric ordering,
independent exact/short/full-width policies, defaults and full-width ordinals. Verify copied values,
source/map identity, detached lifetime, hash-free preparation and 1,000 ARC cycles. Add strict
result/privacy/nominal guards and the registered native suite; run inventory, Python tooling and
pinned formatting. Reuse unchanged finalizer, collector and PVM evidence.

C(13) coordination with other activity, last-accumulation account timestamps, queue/history updates,
transfer/account/privilege integration and whole-block publication remain open. M1 framing is
complete; full state serialization and accumulation/block parity remain open.

## Local verification

Passed `make unit SUITE=accumulation_statistics`. The four-round signed fixture yields six
work-items and 132 actual gas: service 42 has four items/66 gas and service 99 has two items/66 gas.
The six-round fixture traverses three dispatched reentries and a terminal entry, yielding eleven
items/220 gas: seven items/110 gas for service 42 and four items/110 gas for service 99. These are
literal independent expectations; declared reservations are never used as consumption.

Missing-code services retain their work-item counts with zero gas. A stopped first continuation
counts only its processed report, preserves allowance-only gas, and omits a service with neither
items nor actual gas. Empty activity accepts zero work/service ceilings. Exact/short/full-width
policies, nominal bounds, copied records/observations, source/full-map identity, detached lifetime
and hash-disabled preparation/queries pass. The 1,000-cycle success/refusal ARC workload retained
1,109,200 occupied bytes before and after.

Five extraction probes and five privacy/nominal compiler rejections passed. Python discovery
passed 443 tests with seven skips; inventory, pinned formatting and diff checks passed. Diagnostic
builds reused existing native libraries. No existing fixture, finalizer, collector, codec or PVM
implementation changed, so their unchanged consumer evidence was reused. Logs are retained under
ignored `build/accumulation-statistics/`; these are local macOS results, separate from exact-head
Linux CI. Queue/history and complete C(13) coordination remain subsequent work alongside the
existing transfer/account/privilege and whole-block gates. M1 framing remains complete; full state
serialization and accumulation parity remain open.
