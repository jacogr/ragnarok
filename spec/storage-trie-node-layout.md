# Compact incremental trie node ownership

## Scope and baseline

Continue native stack 1238 above `e42c652ac266490e8c48eb005d1024602f2aef4b`, within the current
20-PR batch ceiling. This feature keeps implementation, related tests and documentation in one
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
