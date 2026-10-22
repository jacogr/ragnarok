# Sustained storage workload

## Scope and pinned baseline

This tranche starts at merged `dae0b46d54aa535e8d450336ecf3f95ee39427f7` with the
existing toolchain and Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` unchanged.
The existing grouped Perf Storage job owns a separate sustained-publication panel beside its
short-run comparison. Memory, synchronized journal and managed repositories receive matching
prepared physical changes through the public API. No format, default, state interface, checkpoint
trust or protocol serialization change is implied.

## Bounded workload and acceptance

Use 1,024/8,192 initial entries, 256-byte payloads, leading key identities and four writes per
publication. Compare 64/256 publications. Each configuration has three validated warmups and ten
measured samples in each of two opposite backend orders. Inputs and expected complete maps are
prepared outside timing. Repeated updates must remain distinguishable after their byte pattern
wraps; fixture validation must check the full payload, root and local generation.

Measure publication, strict disk reopen, nine-root and current-root reclamation independently.
The retained union is the seed plus the final eight revisions. Journal reclamation and memory
reopen remain unavailable. Record selected file bytes and physical node counts at fixed boundaries;
never label them total filesystem usage or resident memory. Validate historical maps and held views
across compaction, restart and owner close. No OS cache eviction or power-loss claim is made.

Raw observations, typed identities, source/build provenance and exact sample coverage must be
validated before producing statistics or Markdown. Incomplete or failed panels must fail the
owning Perf Storage job and remove stale successful artifacts. Report medians, ranges, order
sensitivity and normalized work without a universal speed threshold.

Optimize only after matching baseline measurements identify a concrete storage-local bottleneck.
Preserve checked ARC/Clang release LTO, all recovery/finality and checkpoint-trust boundaries.
Native process-crash qualification remains distinct from hardware/filesystem power-loss testing.
Existing documented M1 scope remains unchanged; physical framing is not complete JAM serialization.

## Planned dependency sequence

First establish sustained fixture correctness and bounded public-API execution, then independently
validate raw output and statistics, publish the panel through the existing job, and collect matched
baseline evidence. Add focused read/growth/I/O attribution only where it resolves measurement gaps.
Use those results to choose storage-local optimizations, qualify affected recovery consumers and
record the retained/rejected hypotheses. Native stacked PRs use semantic titles and a maximum of 30.

## Update locality

Each sustained configuration has sweep updates across the map and hot updates revisiting 256 keys.
The independent closed-form expected revision distinguishes untouched keys and every revisit.
Raw samples, CSV, aggregation and Markdown require the exact pattern identity; neither locality
can substitute for the other. Generation256 retains its full revision encoding.

At 64 publications the two patterns issue identical writes; physical counters must match as a
positive control. At 256 publications hot keys have been revisited four times while sweep keys
have advanced across 1,024 identities. No locality timing is an OS cache-eviction claim.

## Per-publication latency witnesses

Every prepared publication has one monotonic duration, emitted after all validation. Raw evidence
requires exactly one witness per revision in order, with exact backend/case/sample binding. Their
sum cannot exceed the enclosing publication batch interval. The same per-call clock overhead is
present for all backends; formatting and CSV publication remain outside timing. Structured reports
are reparsed through the same coverage contract, and boolean/substituted values are refused.

## Separate SDK observation

The `storageIoCounts` test executable uses the existing maintained OS observer and disarms every
fault/short-progress control. It observes one complete sample per configured trajectory and emits
only operation counts. Ordinary speed builds compile observation away and never link the
observer. Counter snapshots precede printing; reset boundaries exclude setup, validation,
fixture cleanup and owner close outside the named operation. No production fault hook is added.

## Bounded larger-state cases

Add 32,768-entry sweep trajectories at 64/256 publications while keeping hot/sweep comparisons at
1,024/8,192 entries. The exact case plan is ten trajectories per backend and opposite-order pass.
Fixture policies allow 32,768 values of 256 bytes and 100,000 nodes, with explicit separate aggregate
record/value/frame budgets. Selected snapshot/journal limits remain bounded at 32 MiB. These are
benchmark-only budgets, not a production policy or state-interface change.

## Measured immutable search directory

A three-second sample of the archived checked baseline showed complete graph admission dominating
publication. The initial private repository table derived 257 first-byte offsets from its already
sorted immutable cells. Graph lookup narrows only the binary-search interval; full 32-byte equality,
all routing/cycle/count/byte checks and orphan rejection remain mandatory. Every table constructor
(initial owner, sorted publication merge, image admission and selection clone) derives its own
directory. The physical format, public API and independent root/checkpoint authority are unchanged.

Matched opposite-program-order A/B runs retained three warmups and ten measured samples per pass
on the same host and checked profile. 256-publication memory sweeps improved by 1.565× at 8,192
entries and 1.366× at 32,768 entries; extraction and reclamation also improved. Logs, exact input
hashes and executable identities are under `build/storage-growth-ab-prefix-graph/`. These are
local observations, not production throughput or hardware durability claims. The directory adds
257 machine-word offsets per immutable table; reader handles share their exact table owner.

Public physical-node lookup now uses the same immutable directory after its existing owner check.
It still compares the entire address and returns an independently owned record payload. Matched
A/B runs against the graph-directory implementation measured 1.13–1.27× faster spread resident
reads across the 8,192/32,768-entry trajectories, with essentially unchanged publication cost.
Exact inputs and opposite-order observations: `build/storage-growth-ab-prefix-lookups/`.

The directory now selects 4/8/12 prefix bits from its immutable inventory length. Tiny tables
retain 17 offsets; large tables retain at most 4,097. No untrusted value chooses an arbitrary
directory extent, and colliding prefixes still use full-address logarithmic search. Against the
accepted fixed directory, matched memory publication sweeps improved by 1.386×/1.325× at
8,192/32,768 entries respectively; read and reclamation paths also improved. Evidence:
`build/storage-growth-ab-adaptive-prefix/`. Native image, history, ownership and complete-map
controls pass at the changed widths. The extra directory bytes are private resident metadata,
never serialized records or a claimed memory usage total.

Private traversal and root-union membership now use packed 64-bit marker words instead of one
byte per record. Extent calculation avoids overflow-prone round-up addition; each mark/reset uses
an already validated physical position. Cycle, repeated-subtree and orphan checks are unchanged.
Large marker payloads are about 8× smaller, excluding sequence headers/padding. Matched A/B timings
were broadly neutral, with a small larger-case publication gain; no consistent speedup is claimed.
Repository/image/history ARC controls pass. Evidence: `build/storage-growth-ab-graph-bitmaps/`.
