# PVM / state orchestration consolidation

Use pinned GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`
and vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a`. This is an ownership/API
cleanup; protocol equations, encoding widths, limits and upstream pins do not change.

## Single composition path

Execution produces `PreparedFinalAccumulation`. State consumes it through
`prepareAccumulationComposition` and publishes through `publishAccumulationState`
against the exact original parent. The stopped convenience entry delegates to that
same implementation. Execution selection and effect certificates stay execution-owned;
block-level composition and final caller-store publication stay state-owned.

Retire the older `accumulation_publication`, `ready_reconciliation`, `recent_history`,
`block_preimages` and `block_authorization` orchestration chain. It had no ordinary
production consumers outside that chain. Remove only its obsolete API/compiler/runtime
probes; retain the corresponding canonical state guards and all state suites.
The duplicate ready projection is superseded by `projectAccumulationReady`.
Keep reusable account/history/activity/preimage/authorization projections and their
component tests. These projections do not provide another whole-block entry.

## Shared fixture boundary

`SignedBlockFixtureConfig` in `tests/support/state_report_admission_context.nim` owns
original-parent entries and signed-block inputs. `authored` accepts that one value.
`ExecutionFixtureConfig` in `tests/support/state_accumulation_execution_context.nim` owns
PVM guest/allowance/role inputs and embeds the exact signed configuration. It passes
that value to the signer, overriding code and merging extra entries before signing.
Construct configurations with `signedBlockFixtureConfig()` / `executionFixtureConfig()`;
these preserve their deliberately different incoming-report defaults (two / zero).
Callers customize fields explicitly; extending signed inputs no longer requires
copying another positional/optional forwarding signature into the PVM helper.
Unsigned batch-host witnesses remain PVM-local fixtures with their own existing policies.

## Coverage preservation

| Retired path | Retained independent witnesses / state coverage |
| --- | --- |
| Combined timestamps/history/activity batch | `accumulation_statistics`: literal E4 timestamps, processed-prefix C(15), active/empty/pending cases; `accumulation_times`, `accumulation_history`, `accumulation_activity`: complete-map and bounded projection tests |
| Ready reconciliation | Migrated literal ready/dependency/expiry/single-slot/profile witnesses in `accumulation_statistics`; `accumulation_ready`: exact/short input/output budgets, malformed sources, complete-map parity and ARC |
| Recent history | Migrated sealed-header, original-parent correction, guaranteed package pairs, literal four-leaf Keccak tree and C(3) framing; `accumulation_recent`: limits/backend/codec/map/ownership coverage |
| Block preimages | Migrated empty-blob/guest-provided/unsolicited/duplicate/unordered/malformed/prior-supplied witnesses through canonical composition; `accumulation_preimages`: full-map roots, no-op behavior, quota/hash refusal and ownership |
| Block authorization | Migrated empty/one/two-guarantee, duplicate/full pools, real assign and manager witnesses; `accumulation_authorization`: original-pool/posterior-queue semantics, full-map roots, caps/backend/ownership |
| Per-stage mutable publication | `accumulation_block_publication`: exact-parent, equal-root foreign/stale/default refusal, no-hash adoption and detached lifetime; `accumulation_completion`: all-phase failure causes, rollback, direct/wrapper/manual-root parity and ARC |

Completion requires migrated signed witnesses plus affected fixture consumers to pass,
canonical runtime extraction/compiler privacy/nominal guards to remain effective,
inventory/tooling checks and pinned formatting. Production retirement requires no
remaining consumers of those modules after the obsolete tests/probes are removed.
Record observed results below; exact-head Linux CI remains separate evidence.

## Remaining scope

Ordinary merge conflicts remain possible in shared files. New execution effects or
successor contract changes still require coordinated state adoption at this boundary.
The cleanup removes a parallel composition path; it does not establish complete
whole-block parity or complete state serialization. M1 framing remains complete.
Preserve full/light storage separation and the existing independent specification gates.

## Observed local verification

On macOS with pinned Nimony/ARC, Clang LTO and checked contracts/bounds:

- All 35 selected native suites passed: every directly changed suite, signed
  fixture consumers, continuation/reentry/transfer histories and the canonical
  history/ready/recent/times/activity/preimage/authorization/consensus/publication
  phases. Each suite retained its required unchanged 1,000-cycle ARC baseline
  (35,000 cycles total). Completion retained 3,471,584 bytes; the migrated
  statistics/integration suite retained 1,588,944 bytes.
- All 104 canonical runtime extraction probes across eleven phase/completion/
  publication families passed strict exit/diagnostic checks. All 60 selected
  canonical compiler privacy/nominal guards retained their intended rejections.
- Inventory plus sixteen targeted inventory/failure-plan/compiler-plan tooling
  tests passed. Pinned Nim/Rust format-check and Git whitespace checks passed.
- An import scan found no remaining consumers of the five retired modules.
  The only matching source words are references to the GP recent-history chapter.
  The reusable component projections and all native state suites remain.

Logs and observed per-suite ARC results remain under
`build/pvm-state-consolidation/`, with native runner logs under
`build/tests/native/selected/`. Exact-head Linux CI remains separate evidence;
these local results do not establish complete whole-block parity.
