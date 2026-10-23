# Compact incremental trie node ownership

## Scope and baseline

Continue native stack 1238 above `e42c652ac266490e8c48eb005d1024602f2aef4b`, within the current
15-PR batch ceiling. This feature keeps implementation, related tests and documentation in one
PR. It changes only private incremental-trie representation; no state/application integration,
public API, physical record/disk format, compiler/provider pin or allocator is changed.

The physical repository's compact `StoredRecord` and the incremental trie's `TrieNode` are
separate owner populations. The repository's earlier 62.2 MiB retained floor is not a trie
measurement and is not reduced merely by changing incremental nodes.

`make unit SUITE=full_state_trie_footprint` observes graph, one copied update path and one retained
leaf after all revisions retire. Construction source maps and independent `stateTrieRoot` scratch
retire before observation. Fifteen count/value cases (0/1/32/512/8192 entries, 0/32/256-byte values)
run in reversed full order and require identical live allocator receipts, exact independent
roots/counts, all source values after mutation, surviving leaf bytes and exact release.

The baseline panel on Apple M1 Max/Darwin 27 ARM64 records 144 allocator bytes per node plus
owned payloads and a 64-byte revision. At 8192 entries/16,386 nodes, empty values retain
2,359,648 bytes and 256-byte values retain 4,456,800 bytes. A held zero-value leaf retains
144 bytes, independently of the original graph size. Baseline receipts are preserved in
`build/storage-db12-footprint-baseline.tsv`.

## Selected representation and invariant

Leaves have exactly one entry and one nonempty node; their value-byte total is their owned
payload length. Keep those totals derived instead of stored. Branches keep cached aggregate
entry/node/value totals and nullable children. A private immutable leaf discriminator selects
leaf key/payload versus branch child/aggregate fields. Complete digest and private hashed state
remain common, and only unpublished nodes may receive their computed digest.

Entry/node/value helpers must handle nil, leaf and branch separately. Replacement/deletion
preflight must subtract derived leaf payload length before allocating candidate paths. Preserve
all existing exact policy arithmetic, unary routing, singleton collapse, complete roots, no-op
identity, copied caller values, immutable old revisions/forks, cached hash reuse and atomic
backend refusal. Leaf and branch constructors set their alternatives explicitly; no public
trusted constructor, alternate decoding or custom allocator/ARC hook is introduced.

Qualify with the public footprint panel, existing full-trie/private observer/published replay
suites, affected StateStore contracts/failure/retention/slice/checkpoint consumers and storage
restore/export consumers. Keep the existing 1,000-cycle ARC observer requirement. The maintained
optional `measure-state-store` target can compare the fixed public consumer workload against the
Git baseline with matching checked flags/providers, without changing that workload or routine CI.
No timing, resident-pressure, power-loss, out-of-core or full-JAM parity claim follows from live
allocator measurements. Existing documented M1 framing/implemented-scope migration completion
remains distinct from complete JAM state serialization and whole-client parity.

## Measured node-layout result

Clang's exact generated-C layout shows a 128-byte baseline node body and 136-byte ARC owner,
compared with an 88-byte candidate body and 96-byte ARC owner (alignment 8). Body/owner size
falls by 40 bytes; ordinary allocator rounding changes the observed owner charge from 144 to 96,
a 48-byte saving per physical incremental node. This is not inferred from unrelated RSS peaks.

| Entries | Value bytes | Nodes | Baseline graph bytes | Candidate graph bytes | Saved bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0 | 0 | 0 | 64 | 64 | 0 |
| 1 | 0 | 1 | 208 | 160 | 48 |
| 32 | 0 | 74 | 10,720 | 7,168 | 3,552 |
| 512 | 32 | 1,030 | 164,768 | 115,328 | 49,440 |
| 8,192 | 0 | 16,386 | 2,359,648 | 1,573,120 | 786,528 |
| 8,192 | 256 | 16,386 | 4,456,800 | 3,670,272 | 786,528 |

All fifteen cases preserve exact independent root/count expectations in both full orders. Every
nonempty graph saves exactly 48 times its node count, and every held leaf saves 48 bytes. The
source graph's size does not affect the held leaf's footprint. At 32/512/8192 entries the selected
single-key update observation falls from 2544 to 1728 bytes for empty source values, and from 3056
to 2240 for 256-byte source values. Those call-boundary observations share identical synchronous
input temporaries; they are not process high-water values or total allocation counters.

The test separately calibrates ordinary payload allocation, caps retained graph ownership below
128 bytes per node plus payload/revision allowance, and caps singleton owner cost below 128 bytes
plus payload. It requires exact release of the update path while source/leaf owners remain,
then exact release of the leaf after every revision is gone. This catches a representation or
lifetime regression without exporting private node or allocator access.

Raw evidence: `build/storage-db12-footprint-baseline.tsv`,
`build/storage-db12-footprint-candidate.tsv`, `build/storage-db12-footprint-comparison.json` and
`build/storage-db12-node-layouts.json`. The latter preserves generated-C identity and exact
Clang layout records. Four existing compiler privacy guards still reject revision, leaf owner,
result status and result payload access with the expected private-field diagnostics.

## Functional qualification

The new footprint suite and nineteen affected existing native suites pass locally: core trie,
private sharing/hash-prefix failure observer, published trie replay; StateStore, contract,
incremental/failure/replay/checkpoint-update suites; checkpoint-bank replay and checkpoint;
physical node export, repository, backend contract, disk replay, disk StateStore, managed disk
StateStore, disk-store hash failure and historical roots. The private observer retains all
1,000 success/refusal/recovery ARC cycles and exact unchanged source/held-value checks.
Inventory and full pinned formatting also pass. This is scoped local evidence, distinct from
full Linux CI, whole-client verification or earlier resident-pressure results.

## Fixed public StateStore comparison

`STATE_STORE_BASELINE_REF=e42c652ac266490e8c48eb005d1024602f2aef4b make measure-state-store`
passes using the unchanged maintained workload, compiler/providers and checked ARC/Clang LTO
profile. Baseline production sources come from the explicit reviewed Git commit; the measurement
tool checks unchanged compiler/crypto inputs and archives only regular project sources. The
candidate measurement head is `8377aa1b11bbcf67bdf41cd9a621e78aa9409afb`; the subsequent commit
changes qualification prose only. Each binary runs in two fresh processes with identical complete
samples. The fixed workload source SHA-256 is
`cdcc5eb91e2493e1d92d41bae36588b84225f5a939ed235eb5ba2bae611533b1`.

| Entries | Snapshot window | Baseline retained bytes | Candidate retained bytes | Saved bytes | Hash calls, both |
| --- | ---: | ---: | ---: | ---: | ---: |
| 128 | 1 | 128,496 | 108,048 | 20,448 | 640 |
| 128 | 8 | 237,728 | 214,784 | 22,944 | 640 |
| 1,024 | 1 | 1,079,456 | 873,776 | 205,680 | 1,152 |
| 1,024 | 8 | 1,805,136 | 1,596,960 | 208,176 | 1,152 |

Initialized and sampled live-heap maxima also fall in all four cases. These are occupied ARC
checkpoints after fixed operations, not total allocation counts or process RSS. Hash-work counts
remain exactly unchanged; the workload independently validates complete final roots and maps.
StateStore's existing sorted mapping and its separate value copies remain present, so its savings
are distinct from the standalone trie panel. No throughput claim is made.

Complete report: `build/storage-db12-state-store-measurements.json`; original build/run logs
remain in `build/tests/state-store-measurements/`. Raw per-suite evidence and exact source/config/
compiler/provider identities are recorded in `build/storage-db12-final-verification.json` and
`build/storage-db12-selected-checks.json`. The existing physical repository representation and
its prior reopen/pressure qualification are not relabeled as results for a new storage layout.

## Completed scope and next decision

This bounded increment qualifies smaller incremental nodes, copied paths and retained leaves,
with measured public StateStore savings and unchanged hash work. The next representation decision
should start from these measured owner costs and retained-snapshot needs. The complete graphs
remain resident; a database larger than RAM still needs separately specified bounded working-set
ownership and on-disk graph authority. Allocation exhaustion, external checkpoint authority,
full/light startup and whole-client protocol serialization retain their separate gates.
