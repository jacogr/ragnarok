# Terminal-selected outputs of an admitted accumulation round

## Scope and authority

Collect service/output pairs from an existing `CompletedBlockAccumulation`, retaining that exact
admitted execution source. Authority remains GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation.tex SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f` (`accpar` B and
`finalstateaccumulation`), and pvm_invocations.tex SHA-256
`67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb` (collapse C).
Root semantics and their pinned references remain those of the [history contract](history-transition.md);
[the C(16) codec](state-outputs.md) continues to preserve caller sequence order.
Pins, byte-domain interpretations and the parked request-domain question do not change.

Use only the already normalized terminal-selected outcomes. A present all-zero commitment is a
real pair; absence contributes no pair. Panic/out-of-gas selects checkpoint yield state, while a
readable 32-byte halt return already overrides it in normalization. Never normalize or execute
again. Sort this single-round unique-service set numerically, independent of execution order.
Equal commitments from different services remain distinct pairs.

Bound executed-outcome traversal independently of output count and full canonical log bytes.
Prove typed row and count-prefixed wire extents before allocation. Preparation performs no hashes
or state writes. Expose copied records, fresh one-round C(16)-format encoding and an explicit root
adapter reusing the existing history algorithm and its failure reasons. Retain source ownership
through every query and refuse defaults without fabricated empty logs or roots.

The encoded log/root represents this supported initial round alone, not the final multi-round
block output set. No C(16)/history chapter publication, emitted-transfer collection, privilege/account
mutation merger or later-round scheduler is added here. M1 framing remains complete; full state
serialization and accumulation/block parity remain subsequent work.

## Completion tests

Use genuine signed completed rounds and actual guest yield/checkpoint/halt-return behavior.
Check rollback/absence, readable override, unreadable return, present zero hash, equal hashes on
different services, sorted output order, exact/short traversal/count/wire ceilings, empty/all-skip
rounds, retained source lifetime, immutable copied observations and no preparation hashes.
Compare literal one-round log bytes and independent raw Keccak leaf/node transcripts. Inject root
backend refusal, retain source after failure and repeat 1,000 ARC cycles. Add strict extraction,
privacy and nominal guards; run the new suite plus affected execution-fixture consumer, Python
provenance/reference tests, source-owned inventory and pinned formatting.

## API and ownership

`prepareAccumulationOutputs` accepts only a `CompletedBlockAccumulation` and separate executed-outcome
and output-log ceilings. It scans presence without hashing, proves the complete native/count-prefixed
wire extents, captures fixed service/commitment values, and sorts the unique-service round set.
The private acyclic owner retains the completion and independent values; it exports no mutable array.
Skipped services contribute no terminal outcomes or pairs, while initialized empty rounds remain
valid and distinguishable from default handles.

`outputsInfo` returns copied cardinality and wire extent. `outputsSource` retains the exact completion.
`outputAt` accepts the nominal output-log ordinal, validates full-width bounds before narrowing,
and returns a fixed independent pair. `outputsEntry` asks the existing codec for fresh independent
one-round C(16)-format bytes on each call; it performs no store write. `outputsRoot` explicitly invokes
the existing ordered history root algorithm under the retained limits. Empty roots require no hash;
backend failures retain only a guarded `HistoryFailure` reason and leave the owner usable for retry.
Root derivation is explicit and uncached; callers can retain successful returned values.

No normalization, guest execution, bootstrap hashing or full-state Merklization is repeated by
preparation. The output ceiling bounds retained yields, while the execution ceiling bounds distinct
outcomes traversed even when every yield is absent. Two fixed passes avoid allocating an oversized
candidate under a short wire budget. Equal commitments on different service IDs are not duplicates.

## Local verification

Passed `make unit SUITE=accumulation_outputs` with genuine signed rounds and real guest code for
yield/halt, uncheckpointed panic, checkpoint rollback, readable halt override, unreadable return and
present all-zero return. Literal canonical 73-byte two-pair log bytes and raw Keccak singleton/internal
node transcripts verify framing, numeric service ordering and history integration. Reversing execution
order preserves bytes/root; equal hashes on two services retain both pairs. All-skip, no-yield and
empty rounds, exact/short independent ceilings, default/full-width bounds, source lifetime, copied
entry/record isolation, backend refusal/retry and hash-free preparation/encoding are covered.
The 1,000-cycle ARC workload retained 711,904 occupied bytes before and after.

Eight strict extraction probes and five privacy/nominal compiler rejections passed. The shared signed
execution fixture gained optional complete authored program preimages; its default code/allowance
paths remain unchanged and `make unit SUITE=accumulation_execution` passed as its consumer, retaining
1,063,584 occupied bytes before/after 1,000 cycles. The static report
fixture remains checksum-verified and needs no generated corpus setup. Python discovery passed 441 tests with six skips; source-owned inventory/provenance, pinned
formatting and diff checks passed. No PVM, codec, history algorithm
or batch implementation changed; their existing evidence is reused.

Logs and diagnostics are retained under `build/accumulation-outputs/`. These are local macOS results,
separate from exact-head Linux CI. The [continuation planner](accumulation-continuation.md) now selects the next report-only prefix
from actual remaining gas and the original admitted queue. Range input/state binding and
transfer-aware execution and block publication remain subsequent work.
[Retained history collection](accumulation-reentry-outputs.md) now unions the selected full pairs
across genuine completed initial, continuation and repeated reentry rounds.
