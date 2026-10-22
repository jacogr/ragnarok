# Current deferred-transfer scheduling

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
fnpartitionxfers, eq:accseq and eq:accinvocation. Integrate the checked pending
owner and stable partition into authenticated continuation/reentry preparation.

Initial continuation owns newly emitted transfers. Later entries concatenate the
previous input partition's queued subsequence before new output, deriving actual
usage from the retained producer collection. Preserve the existing new-output
count/gas observations, and expose pending/partition owners separately. Select
reports only after reserving old queued gas; refund only newly emitted paid gas.
Always-accumulate allowances never recur.

Materialize selected report services, apply the actual preceding batch privately,
and resolve supervision from that complete post-batch state. Only accepted
transfers become invocation inputs; retain queued transfers for the following
entry. Empty transfer sequences need no supervision checks. Nonempty partitioning
requires explicit transfer/service/check limits in materialization configuration;
zero limits grant no nonempty work. Preserve safe operand/count preflights before
state work. Metadata-dependent classification and final input grouping occur after
the private batch succeeds; refusal never publishes the candidate to a caller.

Completion witnesses must include real scheduled supervisor/recipient cases,
queued-only later entries, ordering across old/new output, no repeated refund,
post-batch supervisor incarnations, skipped/missing code, exact limits and nested
errors, stopped/depth behavior, immutable source ownership and fresh ARC release.
Foreign account publication remains a separate modified-account selection gate.

## Local verification (2026-10-22)

All266 production modules and15 affected native suites pass, including fresh
1,000-cycle ARC evidence. Genuine signed transfer chains cover both a preexisting
supervisor and supervision changed by the preceding guest, accepted-only grouping,
old queued records before new output, held gas reservation without repeated
refund, carried-only zero-gas dispatch and complete drain into final statistics.
The combined carried/new input group uses an explicit larger test execution cap.

All36 selected runtime result guards and45 compiler privacy/nominal guards pass.
Python reference/tooling verification passes639 tests with3 existing skips; the
changed failure/verification harnesses and inventory receive focused final checks.
Formatting and diff checks pass. Full evidence stays under
`build/transfer-scheduling-*` and `build/tests/transfer-scheduling-*`.

This implements the pinned scheduling equation without a new GP discrepancy.
Local macOS checks do not establish Linux CI or complete JAM host interoperability.
Foreign account publication remains gated pending accpar annulment and account
selection; no compiled benchmark or additional fuzzing CI is claimed here.
