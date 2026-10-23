# Bounded stable retained-root inventories

Scope: remove quadratic duplicate detection from `selectRepositoryRoots` in
`src/storage/node_repository.nim`. Existing graph, root authority, image order and disk contracts
remain unchanged. This feature owns its implementation, dedicated suite and independent fixture.

## Algorithm and contract

The selector still bounds every borrowed root slot before deduplication, requires the current
complete root before graph traversal, and validates each distinct root independently. A private
root/ordinal array sorts complete identities, breaking ties by caller position. Adjacent equal
identities mark later positions in a bounded bitmap. Sorting scratch retires before an exact-size
output copies the original first occurrences in caller order. No mutable input/output aliases or
sorting descriptors survive in the selection. The public retained-root order is preserved.

Deduplication now takes O(r log r) full-root comparisons and O(r) bounded temporary storage,
instead of O(r squared) comparisons for distinct roots. RootSlot extent is checked against native
addressing before allocation; bitmap rounding uses division/remainder without count+63 overflow.
The existing graph and union traversal cost remains separate. This does not cache graph authority,
change hash behavior or bypass any per-root topology/value/route budget. Duplicate slots count
against the caller's original ceiling; failed/default selections still carry only their reason.

## Verification and performance acceptance

`make unit SUITE=storage_root_inventory` covers 4096 distinct singleton historical graphs plus the
empty root, reversed first-occurrence order, adjacent and distant duplicates, exact/short limits,
missing selected roots, late unknown roots, copied input/output ownership, closed source owners,
independent clones and 1000 scoped ARC success/refusal cycles. A primitive observer refuses all
hash calls during selection and requires zero attempts. Existing retention, images, historical
roots and compaction suites remain the affected consumers.

Measurement must compare the same fixed full public selection workload and native profile against
parent `99746f106056f36cc6a67ca07b4d1b9028c12949`, preserving full root order and counts. No speed
claim is made for small inventories. The measured candidate is `ff5bef38`; later changes in this
layer are documentation only. Nine selected native suites, inventory and pinned formatting pass.

The checked macOS ARM64 ARC/Clang release/LTO probe builds the same independently validated
4097-root history, selects a reversed twice-repeated list four times, checks all output roots,
4096 physical records, zero hash attempts and exact owner retirement. Identical probe/fixture
bytes compile against parent/candidate archives using the maintained native build helper. Python
`perf_counter_ns` measures serial fresh processes, with three warmups and ten paired samples in
each order (`hyperfine`/`valgrind` are unavailable). These timings include identical fixture setup.

| Order | Parent median | Candidate median | Reduction |
| --- | ---: | ---: | ---: |
| baseline-candidate | 55.30ms | 10.26ms | 81.5% |
| candidate-baseline | 56.39ms | 10.49ms | 81.4% |

The algorithmic change and this large distinct-inventory workload justify retaining the fix.
No small-inventory speedup or disk-recovery/RSS improvement is inferred. Complete commands,
source/compiler/library SHA-256 identities, raw samples and spread are in
`build/storage-db14-measure/timing.json`, using `build/storage-db14-measure.json` and
`build/storage-stack-measure.py`. Native results are in `build/storage-db14-selected-checks.json`.
This adds no routine performance matrix or remote CI request; exact-head Linux CI remains separate.

## Boundaries

Physical graph ownership and per-root graph validation remain unchanged. This improves root-list
preparation, not a bounded working set or full-graph residency. M1 framing is complete; full JAM
state serialization and whole-block parity remain open. Continue through measured substantive
stack increments within the maintainer's 15-PR cap; do not create layers solely for tests or docs.
