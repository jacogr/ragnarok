# Selected manager publication

Implement pinned GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`accumulation.tex` accpar and R, with vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Preserve all pins and host semantics.

Retain successful bless occurrence provenance with immutable implication snapshots,
including checkpoint/terminal selection. Permit only this proven C(12) change to
preserve account scope; unsupported ancestry remains sticky. Publish manager and
always-accumulate entries from the original manager's terminal-selected outcome.
For each assigner, delegator and registrar apply R(o,a,b): take the manager's
choice when it differs from the original role, otherwise the original owner's
selected choice. Queue contents still come from the original assigner's outcome.
Absent/skipped authorities retain initial state. Designate/staging remains gated.

Existing assignCores/assignBytes bound complete positional C(2)/C(12) merging,
including the larger original/output C(12) extent. Selected bless additionally
requires managerEntries and managerBytes, default zero: bound the larger original/
selected dictionary and aggregate original plus output C(12) bytes before capture,
allocation or encoding. Even restored-equal bless requires its explicit budget.
All writes and provisions publish on the same private complete-map fork with exact
input/prior/slot ownership, inherited store limits and all-or-neither rollback.

Completion tests: real manager/assigner executions, changed/unchanged manager
choices, original queue authority, reversed execution order, halt/panic/checkpoint,
restored-equal bless, allowance growth/shrinkage, full-width roles/gas, absent
manager, copied observations, zero/exact/one-below quotas, inherited-store refusal,
hash rollback/retry, literal complete-map entries/roots and ARC release. Retain
unsupported staging and affected host/account/publication regressions.

Next: selected validator staging publication. M1 framing remains complete; full
state serialization and block parity remain open. Full/light separation and
remaining whole-block validity gates are unchanged.

Observed local verification (macOS, pinned Nimony/ARC and native crypto):

- `accumulation_manager_publication` passed literal whole-map entries/roots for
  manager precedence and original-assigner fallback, reversed execution order,
  halt/hash-return/panic/checkpoint selection, restored-equal bless, allowance
  growth/removal, full-width roles/gas, absent manager and manager-only subsets.
  Default-zero, exact, one-below and full-width policies, inherited-store refusal,
  early/late hash rollback/retry, stale callers, copied observations and sticky
  designate-then-bless refusal passed.
- Eleven affected suites passed: `pvm_accumulation_bless`,
  `accumulation_assign_publication`, `pvm_accumulation_assign`,
  `accumulation_effects`, `accumulation_batch`, `accumulation_complete_batch`,
  `pvm_self_account_writes`, `accumulation_execution`,
  `accumulation_continuation_execution`, `accumulation_reentry_execution` and
  `accumulation_statistics`. The bless suite checks provenance across subsequent
  yield/storage, panic and OOG checkpoint selection. The genuine signed-block
  pipeline preserves the selected C(12) through finalization, statistics,
  accumulation publication, ready/history/preimage and authorization coordination.
- All twelve suites retained unchanged occupancy across their 1,000-cycle ARC
  observations. The new suite retained 192 bytes; its per-case plan/publication
  cycles also retained identical before/after occupancy. The signed-block suite
  retained 2,392,784 bytes before and after.
- All 55 existing effect/batch runtime extraction guards passed with their exact
  assertion diagnostics. Both changed production modules and the block-authorization consumer passed
  semantic compilation. All 13 existing effect/batch privacy rejections and 20
  nominal rejections passed with intended diagnostics. Verification inventory,
  all nine inventory tooling tests, pinned Nim/Rust formatting and whitespace
  checks passed.

Full logs and selected guard evidence remain under
`build/pvm-manager-publication/`. These are local results; exact-head Linux CI
remains separate evidence. This increment does not complete block parity.

After merging state integration master `6033e8cd`, the shared execution fixture
retains master's state/history/authorization/store options and appends the manager
option without shifting existing positional arguments. Fresh local
`accumulation_statistics`, `accumulation_runner` and `accumulation_completion`
suites passed, each with unchanged 1,000-cycle ARC occupancy. Pinned formatting,
verification inventory and whitespace checks passed. Merge verification logs are
`build/pvm-manager-publication/merge-*.log`; exact-head Linux CI remains separate.
