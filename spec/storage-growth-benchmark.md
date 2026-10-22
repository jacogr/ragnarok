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
