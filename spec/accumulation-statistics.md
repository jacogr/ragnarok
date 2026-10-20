# Accumulation statistics from finalized execution

## Scope and authority

Derive the accumulation statistics mapping S(s)=(N(s),T(s),G(s)) from a genuine
`PreparedFinalAccumulation`. Authority remains GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation.tex SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`,
`accumulationstatisticsdef`. N counts every work-digest in the processed original report prefix,
including services whose code could not execute. G sums actual certified service gas across initial,
continuation and repeated reentry rounds, including allowance-only executions. For the supported
transfer-aware finalization T counts every processed transfer by destination, including
ordered duplicates, zero-gas/value records and skipped-code recipients. Derive each count
from the actual completed round's bound input group. See
[processed-transfer statistics](pvm-transfer-statistics.md) for the bounded extension.
Omit exactly the all-zero tuples; zero-gas services with work-items or transfers remain.
Order the resulting dictionary by numeric service.

## API and ownership

`prepareAccumulationStatistics` accepts the finalization certificate and independent local limits
for completed rounds, inspected gas rows (including skips and zero-gas rows), processed reports,
work-digests, processed transfers and retained nonzero services. Default zero transfer
capacity authorizes no processed transfers; an explicit count policy enables them. Derive both
report provenance and all round completions
through that exact finalization's output owner; callers cannot substitute rows, reports or gas.
Bounds precede descriptor/candidate allocation. Candidate storage is bounded by gas rows plus
work-digests, with native extent proofs. Sort candidates and combine by service in O(R + C log C) time
and O(R + C) scratch for R rounds and C candidate rows. Prove gross actual gas sums against the
initial budget minus terminal remaining gas
plus every paid outgoing-gas refund represented in completed later-round inputs.
Refuse gross totals beyond uint64 with local LimitExceeded before candidate allocation;
per-service sums are nonnegative subsets of that checked total. Work-item sums are bounded by the
preflighted digest count; transfer sums by the preflighted processed-transfer count.
Full-width local ceilings never become unchecked allocation sizes.

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

[Account timestamps](pvm-accumulation-timestamps.md) now update existing active accounts privately.
[Service activity](pvm-service-activity.md) now coordinates refinement/provision fields with these deltas.
Complete C(13) assembly, queue/history updates,
transfer/account/privilege integration and whole-block publication remain open. M1 framing is
complete; full state serialization and accumulation/block parity remain open.

## Original report-only local verification

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
Linux CI. [Accumulated-package history](accumulation-history.md) now advances C(15) on a private
full-state candidate. C(14)/C(3) and complete C(13) coordination remain subsequent work alongside the
existing transfer/account/privilege and whole-block gates. M1 framing remains complete; full state
serialization and accumulation parity remain open.
