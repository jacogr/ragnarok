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
item/value ceilings. Distinct routed keys partition before the248-bit domain ends. Source nodes
remain immutable; new nodes form an acyclic graph. Construction copies each affected shared path
once. Sorting and preflight remain bounded as before; worst-case work is still bounded by write
count times248 key bits, with fewer intermediate allocations on overlapping paths.

Exact final topology still rejects before crypto. The existing left/right bottom-up hashing
publishes only a completely successful candidate; every failed digest retires only private new
nodes. Existing published subtree/value owners survive success, failure and independent forks.

## Verification and measurement acceptance

`full_state_trie_batches` independently compares wide128-key permuted/reversed mixed batches
against flat512-slot maps and the separate full-map root calculator, crossing empty/inline/long
values and deep shared prefixes in both root polarities. It checks source retention, later input
mutation, a512-write complete swap at exact256-entry/value quotas, empty-source mixed edits,
complete deletion and exact owner retirement. The private suite adds every failure prefix for a
six-write shared-prefix mutation with an untouched old leaf, plus no-hash multi-key absent deletes.
Existing topology, fixture replay, retained footprint, ARC and StateStore/disk suites remain the
affected consumers. No public optimization switch or caller-supplied validation token is added.

Compare fixed checked native public workloads against parent `a34f89db` with identical inputs,
provider/compiler/allocator and profile. Supporting tests and measured evidence belong to this
feature PR; no speedup is claimed until results are recorded. Reports live under ignored
`build/storage-db15-*`, without adding routine performance matrices or requesting remote CI.

## Limits

This improves mutation construction, not global history bounds, serialized checkpoint layout,
physical repository graph residency or disk durability. M1 framing is complete; full JAM state
serialization and whole-block parity remain open. Continue coherent measured layers within the
15-PR batch cap, without waiting for approval between ordinary authorized PRs.
