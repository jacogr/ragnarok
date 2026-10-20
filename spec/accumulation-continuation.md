# Initial accumulation continuation prefix

## Scope and authority

Plan the initial recursive entry following a genuine `CompletedBlockAccumulation`. Authority
remains GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation.tex SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`, equation `accseq`:
remaining reports begin after the completed initial prefix, recursive free allowances are empty,
and the recursive budget subtracts actual service gas rather than declared reservations,
then restores paid outgoing gas before reserving it for the next round.
Pins, domain bytes and the parked request-namespace question do not change.

[Completed-round transfer binding](pvm-transfer-continuation.md) now collects selected outgoing
records in numeric service order under explicit execution, transfer-count and memo-byte ceilings.
Defaults still authorize no nonempty transfer sequence. Restore outgoing gas into the recursive
budget and reserve it before selecting reports, leaving the report remainder equal to original
budget minus actual gas. Transfer-only work dispatches even with zero gas and no reports. Bound
remaining-report inspection and digest inspection independently.
A rejected report consumes inspection work but contributes no selected prefix/gas; later cheaper
or zero-cost reports cannot bypass it. Scan only the original admitted queue's unprocessed suffix,
using remaining-budget subtraction before each candidate charge, including mathematical sums
larger than the gas domain. No prior report payload is copied or rescanned.

Retain the exact completed source and original queue; expose copied prefix/budget facts and
immutable selected report handles through a nominal local ordinal. Preparation copies only bounded
fixed transfers and performs no guest execution, hashing, account application, input rebuilding or
state publication. Defaults and
refusals contain no partially selected progress. The selected reports are a plan, not executed
reports; later reentry transfer integration and final block publication remain subsequent work.
M1 framing remains complete; full state serialization and accumulation/block parity remain open.

## Completion tests

Use signed parent-ready queues and actual completed initial services to distinguish actual gas
from reservations. Check exact/short remaining gas, consumed-prefix offsets, whole-report rollback,
zero-cost reports, no bypass, unaffordable mathematical sums, no-pending/blocked/all-skip cases,
independent work ceilings including rejected reports, full-width ordinals, copied observations,
retained source/report lifetime, hash-free planning and 1,000 ARC cycles. Add runtime extraction,
privacy and nominal guards. Run the new native suite and the affected shared execution-fixture
consumer, Python provenance/reference tests, source-owned inventory and pinned formatting.

## API and ownership

`planAccumulationContinuation` takes an actual completed admitted initial round and independent
outcome/report/digest inspection limits. It captures terminal-selected outgoing records under independent count/memo ceilings,
retains the original priority projection, and starts after the source's completed report prefix.
The recursive budget is retained original budget minus verified actual gas plus selected outgoing
gas; that outgoing gas is reserved before report selection. Allowances do not recur. Candidate report gas is subtracted from a temporary remainder and committed only after all
its digests fit. Thus an unaffordable mathematical sum cannot wrap into an accepted report, and
neither earlier digests of a rejected report nor later inexpensive reports alter the chosen prefix.

`continuationInfo` copies the original completed prefix, pending count, selected suffix prefix,
recursive budget, selected outgoing count/gas, declared selected report gas and dispatch flag. Pending reports with no affordable
head are a successful stopped plan, distinguishable from an initialized empty suffix and from a
default owner. `continuationSource` retains the exact initial completion. `continuationReportAt`
uses a nominal plan-local ordinal, checks full-width bounds before offset addition, and retains the
original immutable report owner without reconstructing or copying its payload. The private owner
is acyclic; failed/default result alternatives contain reasons alone, never partial progress.

Inspection caps apply to work actually inspected, including rejected reports/digests, rather than
all remaining reports. Already consumed reports are neither accessed nor charged again. `continuationTransfers` retains the exact completed-round transfer owner. No API
accepts a replacement queue, transfer array, budget, allowance dictionary or caller-authored gas observation.
No posterior state or next-round invocation certificate is implied by report selection alone.

## Local verification

Passed `make unit SUITE=accumulation_continuation` with genuinely signed parent-ready report rings
and real checkpoint/panic executions. Two 208-gas allowances reserve 416 gas, actual execution uses
406, and the recursive 10-gas budget accepts exactly the next 10-gas report. A following 11-gas report
blocks the later zero-gas report. Other witnesses cover short/exhausted budgets, consumed-prefix
offsets, an affordable zero-gas tail, report-level rollback for the mathematical sum `5 + high(uint64)`,
all-skip unused allowances, empty/no-pending cases, exact/short inspection caps, full-width ordinals,
retained report/source lifetime, copied observations and hashing disabled throughout planning.
The 1,000-cycle ARC workload retained 835,056 occupied bytes before and after.

Five strict runtime extraction probes and five privacy/nominal compiler rejections passed. The
shared signed fixtures gained optional ready rows and allowance gas before parent signing; their
existing defaults remain unchanged and `make unit SUITE=accumulation_execution` passed as its
consumer, retaining 1,063,584 occupied bytes before/after 1,000 cycles. The new
suite reuses the existing checksum-verified static report witness without generated corpus setup.
Python discovery passed 441 tests with six skips; source-owned inventory/provenance, pinned
formatting and diff checks passed. Existing PVM, batch, output collection and gas normalization implementations are unchanged.

Logs and diagnostics are retained under `build/accumulation-continuation/`. These are local macOS
results, separate from exact-head Linux CI. Next work prepares the selected report range's inputs
and binds its actual posterior state before later-round execution. Transfer-aware recursion, final
output-set union and full block publication remain separate bounded integrations.
