# Selected validator staging publication

Implement pinned GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`accumulation.tex` accpar stagingset', with vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Preserve all pins and host semantics.

Retain successful designate occurrence provenance with immutable implication and
checkpoint snapshots. Permit this proven C(7)-only mutation to preserve account
scope; unsupported account ancestry remains sticky. Select the complete ordered
roster from the original delegator's terminal outcome, retaining original C(7)
when that service is skipped/absent. A changed manager delegator role affects
C(12) precedence without replacing C(7)'s original-delegator source. Successful
designation by a newly self-authorized manager cannot substitute its roster.

Require explicit stagingValidators and stagingBytes ceilings (default zero).
Bound the larger original/selected roster count, native typed extent and aggregate
original plus output canonical C(7) bytes before capture/allocation/encoding.
Restored-equal designation still requires its budget. Keep the no-designate path
unchanged. Merge C(7) with account/queue/privilege writes and terminal provisions
on the same private complete-map fork, retaining exact input/prior/slot ownership,
physical key uniqueness, inherited store ceilings and all-or-neither rollback.

Completion tests: real designate/bless guests, original-delegator selection under
manager handoff, nonoriginal self-authorization, reversed execution order, opaque
record ordering, six/nine-validator growth/shrinkage, halt/hash-return/panic/OOG
and checkpoint selection, restored-equal provenance, absent delegator, zero/exact/
one-below/full-width quotas, inherited-store refusal, early/late hash rollback/
retry, copied observations, stale callers, complete-map roots and ARC release.
Extend genuine signed-block coordination to retain selected C(7). Preserve host,
account/batch, manager and continuation regressions, including sticky unsupported
account changes followed by designate.

Next bounded PR: converge on one finalized-accumulation successor contract.
PVM owns execution, checkpoint/terminal effect selection and the resulting
complete-map successor; state's existing coordinator owns history, statistics,
authorization, block composition and final publication. Consolidate duplicated
composition adapters around that boundary, retain existing state projections and
validity/ownership tests, and give shared signed/execution fixtures a stable
configuration/ownership boundary. This layer tests selected C(7) through the
existing state driver/completion APIs instead of extending a parallel block
coordinator. Do not broaden this layer into that convergence refactor.

The signed state completion witness uses the existing six-validator profile.
The following [shared successor increment](pvm-state-successor.md) now permits
valid C(7) count changes during later invocation capture while preserving the
admitted active profile. Its witnesses capture genuine published six/nine-roster
successors; complete cross-profile block/epoch parity remains separate.

M1 framing remains complete; full state serialization and block parity remain open. Full/light separation is unchanged.

Observed local verification (macOS, pinned Nimony/ARC and native crypto):

- `accumulation_staging_publication` passed literal complete-map entries/roots
  for six/nine-validator growth/shrinkage, original delegator selection under
  manager handoff and competing self-authorization, reversed order, halt/hash
  return/panic/checkpoint selection and restored-equal designation. Absent
  authorities, copied observations, zero/exact/one-below/full-width policies,
  inherited-store refusal, early/late hash rollback/retry, stale callers and
  sticky untracked-storage ancestry passed.
- Twelve affected native suites passed: `accumulation_completion`,
  `pvm_accumulation_designate`, `accumulation_manager_publication`,
  `accumulation_assign_publication`, `accumulation_effects`, `accumulation_batch`,
  `accumulation_complete_batch`, `pvm_self_account_writes`,
  `accumulation_execution`, `accumulation_continuation_execution`,
  `accumulation_reentry_execution` and `accumulation_runner`. The host checks
  designation provenance across panic/OOG checkpoints and later yield/storage.
  The new signed completion witness uses existing state runner, stopped driver,
  completion and publication APIs, verifying literal selected C(7), unchanged
  parent aliases and exact zero-hash adoption of the composed successor.
- All thirteen native suites retained unchanged occupancy in their 1,000-cycle
  ARC checks. The new suite retained 192 bytes, including unchanged per-case
  plan/publication loops; the completion suite retained 3,228,096 bytes.
- All 55 effect/batch runtime extraction guards, 13 privacy and 20 nominal
  compiler rejections passed with intended diagnostics. The two changed
  production modules and state completion consumer passed semantic checks.
  Inventory, nine inventory tooling tests, pinned Nim/Rust formatting and
  whitespace checks passed. Full evidence is under
  `build/pvm-staging-publication/`; exact-head Linux CI remains separate.
