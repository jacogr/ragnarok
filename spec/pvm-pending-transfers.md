# Pending deferred-transfer ownership

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
fnpartitionxfers and eq:accseq. A next entry receives the previous partition's
queued transfers followed by newly emitted transfers. Only newly emitted gas is
restored to the recursive budget; previously queued gas stays reserved without
being refunded a second time.

This layer owns that ordered concatenation and checks its budget arithmetic,
before continuation/reentry integration. Construct initial queues from a genuine
outgoing collection, and later queues from a genuine previous partition plus a
new outgoing collection. Derive actual usage from retained normalized producer
outcomes rather than accepting a replacement scalar. Capture independent fixed records; retain the exact
producer handles without mutable spans or parent-queue chains. These pure plans
are not certificates of an authenticated complete round.

For input budget g, derived actual usage u, carried gas q and newly paid outgoing gas t,
require u<=g, q<=g-u and t<=u. The next budget is g-u+t, its pending reservation
q+t and its report allowance g-u-q. Prove these sums/subtractions using bounded
unsigned operations, including full-width edges. Bound producer traversal, copied records and memo work before allocation. A default/refused result retains no queue or partial
progress; default and first-entry previous-source queries remain distinct.

Expose guarded nominal record/source queries and a wrapper that partitions the
owned pending sequence against an explicit immutable current prior. Preserve
nested partition failure reasons. Completion witnesses cover ordered duplicates,
zero/full-width gas, exact carry/refund/reservation math, source identity and
lifetime, local limits, failures, guarded/private/nominal APIs and ARC release.

## Local verification (2026-10-22)

The pending suite, existing outgoing-collection suite and partition suite pass
with fresh 1,000-cycle ARC evidence. Checks cover genuine paid duplicate outputs,
actual usage from repeated and empty-output producers, old queued ordering,
repeated carry without a second refund, exact and maximum-width reservations,
source lifetime, copied records and independent producer/record/memo limits.
All 266 modules, 11 strict result/nested-reason probes, compiler privacy/budget/
ordinal/count-unit rejections, focused harnesses and inventory pass. Evidence:
`build/pending-transfers-*` and `build/tests/pending-transfers-guards/results.json`.
These are local macOS checks for the owned queue primitive. Continuation/reentry
integration, complete JAM/PolkaVM host parity and Linux CI remain separate.

Next wire this owner and partition into continuation/reentry. Use the actual
post-batch state for supervision, retain only accepted records as invocation
inputs, carry the queued subsequence forward before new output and keep its gas
reserved during report selection. Existing authenticated completion/batch owners
must supply the budget and producer collection; no raw replacement state or usage
counter is accepted as a scheduling certificate.
