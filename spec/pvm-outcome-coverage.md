# Exact accumulation provider coverage

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
eq:accpar, original gas accounting and both non-executing Psi_A alternatives.
Certify each genuine prepared input service exactly once using an original
normalized execution, an unavailable-code skip or a distinct absent-account proof.
Require the same input/prior owners and invocation slot; equal contents cannot
replace another source. Order retained rows by the canonical input service order.

Retain the exact annulment certificate, original outcomes and non-execution owners.
Cancellation does not erase the original actual gas or coverage. Skips/absence use
zero gas. Check actual per-service gas against its offered budget and the aggregate
against an explicit budget before addition. Never sum declared/offered budgets as
actual consumption, fabricate an executed outcome, or refund canceled gas.

Bound provider counts, final descriptors and predicate work independently. Refuse
missing/duplicate providers, default/foreign owners, slot mismatches, resource/gas
limits and wrong-kind/index extraction without exposing partial rows. Return copied
row observations and guarded kind-specific immutable owners. No hashes are computed.

This is explicit-input execution coverage, not authenticated block/profile authority,
selected state publication or a completed legacy round/history owner. Callers retain
responsibility for authoritative parameters/code limits and complete state-phase
integration. The next runner supplies all three providers from actual preparation
and execution under one explicit parameter/profile configuration.

Tests cover real mixed execution/skip/absence, cancellation without gas refund,
exact ownership/order/slot/budget/refusal checks, kind guards and ARC release.

The mixed-provider native suite passes with fresh 1,000-cycle ARC evidence.
It retains actual protected skip credit and absent identity alongside a real
execution, accepts actual gas despite offered budgets whose sum exceeds u64,
and proves canceled original gas is never refunded in either producer order.
Exact independent limits, copied-kind independence, missing/duplicate/default
providers, foreign input/state owners, wrong slots/kinds/full-width indices and
initialized empty coverage are covered without state hashes.

All 274 production modules,8 strict runtime extraction guards,6 compiler
privacy/nominal/completed-block-domain checks and54 focused harness tests pass.
Inventory, canonical formatting and diff checks pass. Evidence remains under
`build/outcome-coverage-*` and `build/tests/outcome-coverage-*`; these local
checked macOS ARC/Clang observations remain separate from Linux CI and complete
block publication. The compiler explicitly rejects treating this owner as a
CompletedBlockAccumulation.

Next: supply all three genuine providers through one bounded guest runner using
one explicit parameter/profile configuration, then complete selected block state
publication and participating-deletion/statistics integration in a later batch.
