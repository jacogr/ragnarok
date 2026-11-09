# Complete-source global serialization validation

## Scope and current gates

Authority is the current unreleased Gray Paper pin
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, T chapters 1–16, existing
chapter codecs and accepted compact C13 gas policy. PR542 request-domain adoption
is complete; historical namespace and reader “Next” paragraphs are not backlog.
Selected release-format raw maps are historical compatibility evidence. Draft 35 Thin
primitive integration is qualified separately; it is not a missing serialization field.
Independent GP-derived serialization qualification is recorded separately from
unqualified whole-block/STF parity; each retains its own scope.
See [current serialization status](jam-serialization-status.md).
Current-round execution/publication contracts are documented in the owning PVM/state
feature records; they are separate from this serialization adapter.
Public proof RPC binding and root-authority policy belong to RPC; storage has
reported no state-side API/format adaptation requirement for this increment.

## Bounded contract

The [global snapshot validator](../src/state/global_snapshot.nim) owns exact chapter capture,
resource bounds and retained source identity. Its serialization certificate does not confer
complete T(state) parity or validate consensus.

## Completion tests

Use all sixteen independently encoded composition-fixture chapters with an opaque
service row. Check source identity, exact chapter recomposition, independent exact/
one-short aggregate and chapter limits, all missing chapters, all suffixed chapters,
late malformed rollback, default/profile refusals and immutable caller copies.
Run with the hash backend refused and require zero hash calls. Retained certificates
outlive caller stores, and 1,000 ARC validation/refusal cycles return to warmed live
allocation. Require strict extraction/reason runtime controls and compiler rejection
of private state/result storage and partial-view substitution.

## Local verification

The focused `state_global_snapshot` native suite passes all sixteen missing and
suffixed chapter cases, late truncation rollback, independent exact/short policies,
nested codec resource reasons, copied-slot independence and detached source lifetime.
Validation attempts zero hashes with the backend refused. The finalized 1,000-cycle
success/refusal workload retains219,088 live bytes before and after warmup.
All287 production modules pass semantic checking. Four strict runtime misuse
processes require their exact AssertionDefect diagnostics; a genuine sixteen-chapter
success control passes. Four private-field rejections and the exact partial-view
source-type rejection pass. All40 verification-harness Python tests, inventory,
pinned formatting and whitespace checks pass. Evidence is under ignored
`build/global-snapshot-*` and `build/tests/global-snapshot-guards/`.
These are checked local macOS ARC results, separate from exact-head Linux CI,
full current-pin serialization and whole-block/STF parity.

Next: bind the validated complete source to an explicit complete service manifest,
rejecting opaque/unclassified service captures and any unmatched serialized row.
Reuse composition codecs and retain source identity without claiming valid-state
consistency or trusted-root selection.

The follow-up [complete manifest validator](state-manifest.md) now matches all
service entries through explicit typed inputs; opaque captures and unmatched rows
remain refusals. This does not settle the independent parity gates above.
