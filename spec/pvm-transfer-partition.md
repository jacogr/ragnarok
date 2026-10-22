# Deferred-transfer partition

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`accumulation.tex` fnpartitionxfers immediately before eq:accseq, and
`accounts.tex` effective-supervisor definition. Upstream PR539 confirms that
incoming credits must not be discarded by concurrent supervisor execution.

This layer implements the pure stable partition before scheduling integration.
For each transfer in input order, queue it if its present destination's effective
supervisor is another active report/always service or an earlier accepted
recipient. Also queue it if it supervises an earlier accepted different recipient.
Accepted present recipients extend that recipient set; missing destinations are
accepted without entering it. Same-recipient duplicates and self supervision do
not conflict by themselves. Zero amount/gas and the destination balance flag do
not affect classification. Preserve exact record order separately in both outputs.

Use actual canonical metadata and creation slots from one immutable prior.
Missing or recreated supervisors fall back to the destination itself; malformed
metadata is a local refusal. Bound source transfer and active-service input counts,
unique recipient storage and every membership/metadata check before work or
allocation. Query fixed copied records through nominal ordinals; default/refused
plans retain no payload. Plan ownership retains the exact prior and independent
input copies, with no recursive implementation or parent-plan chains.

Completion tests: independent small-graph exhaustive paper predicates, chain/cycle
and duplicate ordering, active services, stale/missing supervisors, absent targets,
zero/full-width fields, exact work and input ceilings, malformed state, copied
inputs/prior lifetime, guarded/private/nominal APIs and fresh ARC release.
Scheduling integration and parallel foreign publication remain subsequent work.

## Local verification (2026-10-22)

The source-owned native suite passes all43,520 independent finite-model cases
(64 current/missing supervision graphs,8 active sets and85 ordered transfer
sequences), plus stale incarnation, missing/corrupt metadata, ordered duplicates,
zero/full-width fields, exact input/work budgets and copied-owner checks. Fresh
1,000-cycle ARC evidence is stable. All265 modules,7 strict partition extraction
probes, compiler privacy/ordinal/count-unit rejections, focused harnesses and
inventory pass. Evidence: `build/transfer-partition-*` and
`build/tests/transfer-partition-guards/results.json`. Local macOS checks do not
claim scheduling integration, complete JAM or PolkaVM host parity, or Linux CI.

The implementation is iterative. The independent test predicate uses fixed graph
and boolean-set inputs rather than reading the production metadata/cache. Each
successful plan retains exact source records and its immutable prior. Runtime
probe setup is validated before intentional extraction, so a failed fixture cannot
masquerade as the intended invalid-output guard.
