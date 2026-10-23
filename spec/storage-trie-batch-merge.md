# Shared-path persistent trie mutation batches

Scope: merge a validated complete-state write batch through `src/storage/full_state_trie.nim`
without repeatedly copying the same affected path. The [trie contract](full-state-trie.md),
public API, hash domains, immutable ownership and inherited policy remain unchanged.

## Algorithm and atomicity

All existing write-count/extent, tag, duplicate, per-value, aggregate write and final-map budget
checks run before candidate construction. Source lookups still release all replaced/deleted
counts and bytes before adding new values. Sorted unique write ranges partition by the next key
bit, using the same bounded binary-search helper as initial construction.

A range with no writes returns the exact source subtree. A single Delete uses immutable removal;
a single Put directly inserts/replaces its final owned leaf, avoiding an unnecessary preceding
remove pass. Multiple writes recursively merge each routed child once. A source singleton is
expanded logically into its appropriate child without allocating temporary branches. Changed
children normalize together only after all their routed edits complete. Unchanged branch children
return the original branch identity, so multiple absent deletes retain the revision without
hashing. Empty and singleton final subtrees collapse with the existing protocol rules.

Each cached aggregate summarizes final subtree children; no candidate sum includes both versions
of a replaced key. Subtrees fit the validated final map extents, including complete swaps at exact
item/value ceilings. Distinct routed keys partition before the 248-bit domain ends. Source nodes
remain immutable; new nodes form an acyclic graph. Construction copies each affected shared path
once. Sorting and preflight remain bounded as before; worst-case work is still bounded by write
count times 248 key bits, with fewer intermediate allocations on overlapping paths.

Exact final topology still rejects before crypto. The existing left/right bottom-up hashing
publishes only a completely successful candidate; every failed digest retires only private new
nodes. Existing published subtree/value owners survive success, failure and independent forks.

## Verification and measurement acceptance

`full_state_trie_batches` independently compares wide 128-key permuted/reversed mixed batches
against flat 512-slot maps and the separate full-map root calculator, crossing empty/inline/long
values and deep shared prefixes in both root polarities. It checks source retention, later input
mutation, a 512-write complete swap at exact 256-entry/value quotas, empty-source mixed edits,
complete deletion and exact owner retirement. The private suite adds every failure prefix for a
six-write shared-prefix mutation with an untouched old leaf, plus no-hash multi-key absent deletes.
Existing topology, fixture replay, retained footprint, ARC and StateStore/disk suites remain the
affected consumers. No public optimization switch or caller-supplied validation token is added.

Compare fixed checked native public workloads against parent `a34f89db` with identical inputs,
provider/compiler/allocator and profile. Supporting tests and measured evidence belong to this
feature PR. The measured candidate is `be2a6f81`; later edits in this layer are docs only.
Sixteen affected native suites, four strict privacy guards, inventory and pinned formatting pass.
The trie footprint table exactly matches the parent. The maintained public StateStore comparison
has identical initialized/sampled peak/retained occupied-memory rows and identical hash counts
(640/1152 for 128/1024 entries), in two complete samples per binary. These live checkpoints are
not allocation totals or process RSS.

Fixed native probes use identical source against parent/candidate archives on macOS ARM64,
with pinned Nimony ARC/Clang checked release/LTO and the same maintained primitive observer.
Python `perf_counter_ns` measures serial fresh processes after three warmups, with ten paired
samples in each order; `hyperfine`/`valgrind` are unavailable. Each process warms the same workload
once, then repeats it with exact occupied-heap retirement. Reporting occurs after the ARC scope.
Both probes use 512 entries, 33-byte values and eight retained revisions, plus an original held
leaf. Each final root, node count and every value matches the independent full-map calculator.

| Workload per pass | Order | Parent median | Candidate median | Reduction |
| --- | --- | ---: | ---: | ---: |
| 96x64 Put batches | baseline-candidate | 21.39ms | 14.59ms | 31.8% |
| 96x64 Put batches | candidate-baseline | 20.91ms | 14.87ms | 28.9% |
| 4096x1 Put batches | baseline-candidate | 35.94ms | 33.11ms | 7.9% |
| 4096x1 Put batches | candidate-baseline | 35.72ms | 33.01ms | 7.6% |

The broad pass performs 96 batches of 64 overlapping Put writes and 19848 hashes; the sparse pass
performs 4096 one-key writes and 73728 hashes. Both hash counts are identical in baseline and
candidate. The constructor-only probe from the preceding layer also remains within spread
(0.4%/0.2% median difference), preserving its earlier construction improvement.

No whole-StateStore throughput claim follows. Its launch-heavy mixed-workload panel had broad
spread: the first panel showed candidate medians 13.2%/32.4% higher, while a preserved repeat
showed 1.6%/8.0% lower. The disagreement and wide ranges prevent a reliable end-to-end timing
verdict; both panels retain exact hash/memory parity. The focused operation probes above support
the mutation improvement, rather than treating noisy process timings as proof.

Reports: `build/storage-db15-selected-checks.json`, `storage-db15-private-guards.json`,
`storage-db15-measure/timing.json`, `storage-db15-single-measure/timing.json`,
`storage-db15-constructor-measure/timing.json`, `storage-db15-state-store-measurements.json`,
and both `storage-db15-fixed-consumer-timing*.json` panels under `build/`. They retain raw timings,
spread, complete build commands and source/compiler/library identities. No routine performance
matrix or remote CI request is added; local results are separate from exact-head Linux CI.

## Limits

This improves mutation construction, not global history bounds, serialized checkpoint layout,
physical repository graph residency or disk durability. M1 framing is complete; full JAM state
serialization and whole-block parity remain open. Continue coherent measured layers within the
15-PR batch cap, without waiting for approval between ordinary authorized PRs.
