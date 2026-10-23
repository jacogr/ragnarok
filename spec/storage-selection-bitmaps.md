# Bitmap-driven retained union construction

Scope: construct exact canonical `RepositorySelection` inventories without per-root growable
record-index lists, a growable union index list, or sorting all selected indices. Preserve all
independent graph checks and public APIs. Source tables and accepted selection representation
remain unchanged; only private selection traversal scratch and inventory construction change.

## Algorithm and authority

A union traversal owns one per-root seen bitmap, one retained-union bitmap, an exact unique
record count/value-byte total and a small growable list of dirty seen-word indices. Before a
record's seen bit is set, a previously empty seen word is recorded once. Before its union bit
is set, a newly retained physical position contributes once to the union count and bytes.
The source's admitted physical cardinality and aggregate values bound these counters.

After each complete root, reset only the dirty seen words and clear their word-index list.
Never use retained-union bits to skip per-root validation: the next root must independently
prove presence, route, key prefix, acyclic/nonrepeated topology, complete-map counts and quotas.
A node already retained under another root is still traversed and checked again. Empty roots
contribute no record or dirty word. Any later failure retires scratch without exposing a plan.
Existing admission and leaf-extraction traversal modes retain their existing collection paths.

After every root succeeds, scan union bitmap words in physical-address order into one exactly
sized index sequence. Only nonzero words require bit scanning; unused final-word bits can never
be selected. The number of written positions must equal the independently accumulated count.
No selected-index sorting or growable per-record list remains in this path. Both bitmaps and
word-list scratch retire before success. The long-lived selection still retains the same exact
indices, private immutable source, detached first-occurrence root inventory and scalar totals.

This changes inventory construction from per-record growth/sort/reset to word-level sparse
reset and ordered bitmap freezing. Initial bitmap allocation and final word scan still depend
on physical source cardinality. It does not cache graph validity across roots, skip historical
root checks, promise a larger-than-RAM working set or reduce the resident graph representation.

## Verification

The expanded `storage_selection_compaction` suite independently builds several complete map
versions sharing most branch/leaf cells. Counts 63, 64, 65, 129 and 257 cross full and partial
bitmap words. Independent full trie exports, complete-digest deduplication and separately
sorted raw-codec bytes supply the exact union oracle for historical/current roots, reversed
order and duplicates. Historical extraction from a closed-source compact clone verifies each
selected complete map and values. Existing empty/disjoint/sparse selection, missing-current,
late-unknown-root failure, caller/returned mutation and 1000 ARC-cycle witnesses remain.

Affected root inventory, retention, selection encoding/lifetime/clone, image admission,
historical-root, managed compaction/bootstrap/maintenance suites remain scoped checks. Exact
compiler privacy diagnostics, pinned formatting and test inventory are publication checks.

Qualification uses parent `b25bade8` and checked native ARC/Clang release/LTO builds with identical
compiler/providers/allocator. A fixed dense map has 8192 entries with 32-byte values; 64 independently
retired plans each retain exactly 16386 nodes (including three required unary branch levels) and 262144 value bytes. A separate fixed sparse-root
probe selects 4097 roots over 4096 complete singleton graphs with reversed duplicates, four plans,
exact root order and release. Both forbid any hash attempt after admission. Record full ordered
samples in both binary orders, unchanged retained footprint, source/build identities and logs
under ignored `build/storage-db18-*`. Report process timing as including identical fixture
construction and assertions, rather than an isolated function timer or a deployment claim.

The measured code is `1065bebb`. Thirteen affected native suites pass, including the expanded
shared-history oracle and exact 1000-cycle release. Matched macOS ARM64 process timing uses three
warmups and ten fresh paired samples in each binary order with unchanged checked release flags.

| Fixed workload | Parent/candidate median, parent first | Parent/candidate median, candidate first |
| --- | ---: | ---: |
| 8192-entry dense map, 64 plans | 140.41 / 81.02 ms | 142.10 / 80.03 ms |
| 4097 sparse roots, four plans | 10.73 / 10.84 ms | 10.62 / 10.60 ms |
| One root in 8192-cell history, 4096 plans | 10.70 / 10.93 ms | 10.56 / 10.89 ms |

The dense workload is 42.3–43.7% lower in process time. Its final retained plan is exactly
135264 bytes in both versions. The sparse-root panel remains within observed spread. The single-root
history panel's candidate medians are 2.1–3.1% higher, also within overlapping sample ranges;
it supplies no speedup claim for sparse selection. The final bitmap scan remains proportional
to the physical table's word count, even for a tiny selected graph. No universal timing or peak-RSS
improvement is claimed. All probes require complete fixed counts, zero hashes and exact scoped
occupied-heap release; reports are produced after measured owners retire.

Full ordered samples, ranges, commands and source/helper/compiler/library/binary identities are
in `build/storage-db18-measure/timing.json`, `storage-db18-sparse-measure/timing.json` and
`storage-db18-one-root-measure/timing.json`. Reproduce with the matching
`build/storage-db18{,-sparse,-one-root}-measure.json` config and
`build/storage-stack-measure.py` in new private evidence directories. Fixed sources and all
consumer/guard/format/inventory logs remain under the same ignored prefix. Hyperfine and Valgrind
are unavailable locally; these are paired fresh-process wall-clock observations, not instruction
counts or an isolated function timer. Source construction and assertions remain in the process scope.

## Limits

Graph traversal still validates every root independently, using binary lookup in the physical
table. Exact accepted inventory footprint is unchanged. There is no disk format, provider,
compiler, allocator, application or StateStore implementation change. M1 framing is complete;
full JAM state serialization and whole-block parity remain open. Scoped local checks remain
separate from exact-head Linux CI and do not expand routine performance CI.
