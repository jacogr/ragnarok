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
record the retained/rejected hypotheses. Native stacked PRs use semantic titles and a maximum of30.
