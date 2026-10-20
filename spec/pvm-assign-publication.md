# Selected assign publication

Use pinned GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`accumulation.tex` accpar authqueue'/assigners' and `R`, with vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Preserve all pins and host semantics.

Successful assign records immutable occurrence provenance alongside its queue and
privilege snapshots, without widening account-change scope. Checkpoint/terminal
selection keeps or discards that provenance with the exact selected context.
Unsupported ancestry remains sticky: bless, designate and other unported
broader effects still cannot become publishable through a later assign or restore.

When a selected context contains assignments, batch preparation requires explicit
assignCores and assignBytes ceilings (default zero). Bound the complete positional
core merge, original serialized C(2)+C(12), native row/hash/allowance descriptors
before copying or allocation. For each core, read the queue and new assigner from
the terminal-selected result of its original assigner, or retain the original row
when that service was skipped/absent. Keep original manager/delegator/registrar and
always-accumulate entries. With manager mutation still gated, R reduces to this
original-assigner selection; no manager precedence rule is guessed or removed.

Merge canonical C(2)/C(12) with existing account writes, then fulfill terminal
provisions on the same private complete-map fork. Preserve all-or-neither batch
publication, exact input/prior/slot provenance, physical key uniqueness and
inherited store limits. No whole-map diff, mutable snapshot view or caller-forged
assignment trace is accepted. No-assignment callers retain their prior work path.

Completion tests: real two-service assign/handoff, distinct core owners and reversed
execution order; halt/panic/OOG/checkpoint selection, repeated/restored assignment,
source ownership/copy isolation, exact/one-below quotas, hash rollback/retry,
complete-map roots and ARC release. Extend the genuine signed-block pipeline to
consume the changed posterior queue in C(1). Keep unsupported manager/validator
mutation regressions and existing account/transfer/provision tests passing.

Next: selected manager privilege publication and precedence. M1 framing remains
complete; full state serialization and block parity remain open. Full/light map
separation and remaining whole-block validity gates are unchanged.

Observed local verification (macOS, pinned Nimony/ARC and native crypto):

- `accumulation_assign_publication` passed literal whole-map roots/entries for
  both original core owners, reversed execution order, panic, checkpoint panic,
  restored-equal assignments and an explicit executed subset with an absent
  original assigner. Default-zero, exact and one-below core/byte policies,
  full-width ceilings, inherited write refusal, early/late hash rollback/retry,
  stale callers, copied observations and sticky bless-then-assign refusal passed.
- The genuine signed `accumulation_statistics` pipeline now publishes an actual
  assign, retains its posterior C(2) through terminal finalization and block
  coordination, and checks the changed slot-two hash in literal C(1) bytes.
- Affected native regressions passed: `pvm_accumulation_assign`,
  `accumulation_effects`, `accumulation_batch`, `accumulation_complete_batch`,
  `pvm_self_account_writes`, `accumulation_execution`,
  `accumulation_continuation_execution` and `accumulation_reentry_execution`.
  The host suite also checks assignment provenance across OOG checkpoint
  selection and subsequent yield/storage. All ten selected suites passed.
- Every reported 1,000-cycle ARC observation was unchanged. The new suite's
  fixture release loop retained 192 occupied bytes; its per-case preparation /
  complete-map publication loops also retained identical before/after occupancy.
  The signed-block suite retained 2,401,232 bytes before and after.
- All 55 existing effect/batch runtime guards, 13 privacy rejections and 20
  nominal rejections passed with the intended diagnostics. Both changed source
  modules and the block-authorization consumer passed semantic compilation.
  Changed Nim sources matched the pinned formatter. Verification inventory and
  all nine inventory tooling tests passed. These are local results; exact-head
  Linux CI remains separate evidence.
