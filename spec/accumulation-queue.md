# Accumulation dependency queue planning

This bounded non-PVM slice implements **History and Queuing**, including `D`, `E`, `Q` and the
candidate-slot rotation, in Gray Paper 0.8.0 `text/accumulation.tex` at
[`07f041d`](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/accumulation.tex).
It computes the ordered **accumulatable** reports. It does not execute them, assert that they fit
this block's gas budget, expire/publish posterior queues or update accumulated history.

## Inputs, binding and ownership

`src/state/accumulation/queue.nim` provides two boundaries:

- `planAccumulationQueues` consumes complete serialized parent C(14)/C(15), immutable available
  report owners and a candidate header timeslot. This is a pure projection, not a block certificate.
- `planBlockAccumulationQueue` requires the private `AdmittedReports` owner produced by complete
  report admission. It derives the exact parent chapters, actual newly available reports from the
  completed assurance stage, candidate timeslot and chain profile. Callers cannot replace those
  with independently supplied reports, state, time or availability results. The bound handle retains
  that admission owner and its derived projection. The report-publication coordinator is unchanged;
  planning is explicitly requested after successful admission/publication and performs no writes.

Reports newly **guaranteed** in this block are not newly **available** merely because admission
succeeded. The adapter takes the earlier assurance stage's output, which may contain a report just
removed from C(10), rather than reading the final assignments and guessing availability.

Private, immutable acyclic ARC owners retain complete reports, decoded parent rings, edited `q`
and the priority sequence. Accessors return copied metadata/hashes or retained report handles;
no mutable sequence or detached byte coordinates escape. The bound handle separately retains its
admission source. Default/refused tagged results contain reasons only; extraction requires selected
success. Priority and dependency indices have separate nominal domains.

## Exact rules

1. Preserve newly available input order when splitting reports with **both** no prerequisites and
   no segment-root lookups into the immediate prefix. History does not remove this prefix.
2. For each other new report, form `D` from the set union of prerequisite hashes and **lookup keys**.
   Lookup roots are not dependency identities. Apply `E` using the union of parent accumulated history:
   drop reports already accumulated and subtract accumulated identities from their dependencies.
3. Flatten parent ready slots starting at `candidateSlot mod epochSlots`, wrap once, then append
   newly deferred entries. Apply `E` with immediate package identities. The pinned equation does
   **not** first apply accumulated history to the parent ready ring, nor expire rows by elapsed time.
4. `Q` collects **every** currently dependency-free report in sequence order as one wave, emits
   that complete wave, then applies `E` using its package identities. Iterate until no ready wave
   remains. Self-dependencies, cycles and missing dependencies remain deferred; this planner does
   not reject the graph or fabricate availability.

No extra sorting/deduplication changes report order. Sorted private hash indices only implement
set membership. Structurally allowed repeated ready reports follow literal `Q`: all ready duplicates
in one wave are emitted, and `E` then drops all occurrences of those identities. This does not
weaken the preceding reporting stage's package uniqueness checks.

The exposed edited queue is the initial `q`, **not** the execution-dependent posterior C(14).
Selecting a report in this priority plan does not imply successful or completed accumulation.

## Resource policy

Existing `WorkQueueConfig` independently bounds decoding of each complete parent chapter, rows,
reports and dependency storage. Full chapter consumption is required. The block adapter checks
byte extents before extracting chapter copies and matches epoch/core domains to the admitted block.

The planning `items` ceiling covers the sum of parent ready entries, accumulated hash entries and
newly available reports, including entries later removed. `dependencies` covers parent dependencies
plus incoming prerequisite/lookup counts **before union**, conservatively charging overlaps twice.
Incoming retained report bytes have individual `reportBytes` and aggregate `maxBytes` ceilings;
owner core/shard domains must fit the selected profile. Host-size proofs precede scratch allocations
and count additions; no wrapping arithmetic is used as a size proof. Resource refusals are typed and
publish nothing. Allocation exhaustion retains the existing fail-stop policy.

`Q` uses bounded iteration rather than recursion: a nonempty wave removes at least one report.
Each wave scans the remaining entries and dependencies with sorted-set membership, so worst-case
long chains require quadratic scans in the bounded input size. No optimization or execution-runtime
claim is made by this slice.

## Verification and reproduction

`make check-modules check-unit check-failures check-guards check-python` runs the affected groups
with pinned Nimony, ARC, Clang LTO and runtime bounds/contracts. Linux CI remains separate evidence.
The feature registers one native suite, seven strict runtime extraction probes, five compiler privacy
probes and two nominal-index rejections. Native allocation evidence requires no retained live-memory
growth over 1,000 success/refusal cycles.

`tests/accumulation_queue_fixtures.py` transports six unchanged pinned accumulation STF inputs:
`accumulate_ready_queued_reports-1`, `enqueue_and_unlock_chain-1` and
`enqueue_and_unlock_chain_wraps-1`, each for tiny and full profiles, from
[`d3c089c`](https://github.com/jam-conformance/jam-test-vectors/tree/d3c089c9a1d5352ad353626d7a2db8589f137b2a/stf/accumulate).
Existing `spec/pins.json` source SHA-256 checks remain mandatory. An independent test-only
set/recursive-sequence reference derives exact complete-report order and edited dependency sets;
the selected package set also agrees with the upstream posterior accumulated-history additions for
all six cases. This is queue-planning projection coverage, **not** complete accumulation STF replay.
Upstream execution results are not synthesized or silently substituted.

Another 256 deterministic authored graphs compare full queue/priority outputs, including incoming
prerequisites/lookups, overlaps, history removal, unknown dependencies, cycles and ring rotation.
Literal native cases independently pin whole-wave order, original parent dependencies, duplicate
rules and immediate-prefix behavior. Python literal witnesses check the reference itself.

The native suite also exercises default owners, truncation, suffix rejection, resource/native-size
bounds, extreme indices/timeslots, retained children and original input mutation. A genuine signed
block with five Ed25519 assurance votes makes one old report available, completes report admission,
then obtains exactly that report through the block-bound planner while hashing is poisoned. The
original complete parent commitment remains unchanged. This nonempty composition case is authored;
it is not presented as an upstream full-block accumulation fixture.

## Remaining work and next bounded slice

Report-derived owned per-service operands have a separate [preparation contract](accumulation-operands.md).
[Invocation inputs](accumulation-inputs.md) add explicit transfer/privilege context, and
[initial round planning](accumulation-round.md) now selects the gas-bounded prefix using admitted-parent
C(12). Service-account execution-context binding comes next. Actual accumulation execution, later
rounds, service mutations and execution-dependent C(14)/C(15) publication remain open; keep those
separate until genuine execution outcomes exist.
