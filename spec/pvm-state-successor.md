# Finalized accumulation / state composition boundary

Use pinned GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`accumulation.tex` partialstate/accseq and `safrole.tex` valcount, with vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Preserve pins and protocol encodings.

Reuse the opaque `PreparedFinalAccumulation` as the single execution-to-state
successor contract. Execution owns real stopped continuation/reentry selection,
terminal effects, actual gas/output history and the complete C(16)-finalized map.
Expose immutable source queue, authenticated admission and exact original parent
through that owner; accept no independently supplied map/profile/header as a
replacement. State consumers obtain original block authority through these
accessors instead of reproducing execution-owner traversal.

State's `prepareAccumulationComposition` consumes this finalized owner and a
state-only policy to run existing history, ready, recent, times, validators,
activity, preimages, authorization and consensus phases. The stopped convenience
entry finalizes once and delegates to that same implementation. Separate
finalization/composition policies, retain precise failure alternatives, preserve
all-or-neither private composition and exact-parent zero-hash final publication.

Staging C(7) cardinality belongs to GP valcount, independently of the admitted
active-validator population. Keep active profile binding and per-roster/item/byte
ceilings, but capture valid six/nine-validator staging successors without demanding
equality to the active population. Do not infer a different chain profile.

Completion tests: direct finalized-owner / stopped-wrapper / independently spelled
state-chain full-map parity; no second finalization on direct composition; default
and forged source rejection; detached immutable source/parent ownership; original
parent publication and stale/foreign refusal; precise phase/hash/quota rollback;
continuation/reentry/yield/staging preservation; staging/active population
independence with exact and one-below limits; runtime/compiler guards and ARC.

This establishes the shared successor boundary. The follow-up
[orchestration consolidation](pvm-state-consolidation.md) migrates the older scoped
PVM witnesses, retires their duplicate publication chain and shares signed fixture
configuration. Reusable projections and state validity/ownership coverage remain.
M1 framing remains complete; full state serialization and whole-block parity remain
open. Full/light separation and independent specification gates are unchanged.

Observed local verification for the first tranche (#247, macOS, pinned Nimony/ARC
and native crypto):

- `accumulation_completion` passed direct finalized-owner / stopped-wrapper /
  independently assembled phase-chain full-map parity for signed ordinary,
  guarantee, available/provided, dispute, ticket, epoch-crossing, repeated and
  yielded histories. Direct composition avoids repeated C(16) finalization.
  Immutable queue/admission/parent access performs no hashes, detached finalized
  ownership survives caller scope, and exact-parent publication adopts the
  complete candidate without hashes. Default/temporary owners, phase quotas,
  nested refusal reasons and late hash rollback retain their intended behavior.
- `accumulation_context` accepts valid six/nine staging populations independently
  of active population, preserving malformed/profile/count/byte refusal and
  exact/one-below aggregate limits. `accumulation_staging_publication` now captures
  real published grown/shrunk C(7) in a subsequent invocation under the original
  active profile. No fabricated block profile is accepted.
- Other native regressions passed: `accumulation_finalization`,
  `accumulation_runner`, `accumulation_later_runner`, `accumulation_driver` and
  `accumulation_block_publication`, including exact-parent/stale/foreign owner
  checks. All eight suites retained unchanged 1,000-cycle ARC occupancy.
  Completion retained 3,472,864 bytes; staging publication retained 192 bytes.
- All thirteen changed production modules passed semantic compilation. All 25
  finalization/completion runtime extraction probes, seven privacy rejections and
  seven nominal rejections passed with intended diagnostics. Inventory, nine
  inventory tooling tests, pinned Nim/Rust formatting and whitespace checks
  passed. The shared signed execution fixture was unchanged.

Evidence remains under `build/pvm-state-successor/`. These are local results;
exact-head Linux CI and complete whole-block parity remain separate evidence.
