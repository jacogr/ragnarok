# Standalone storage records

Scope: detached changed-node persistence foundations under `src/storage/`. GP 0.8.0
`07f041dabd073f9018b418e9ee72e79dd2185401` M/B/L remain authoritative; physical records
are local storage data. No state/checkpoint/PVM/application consumer may adopt this work until
explicitly authorized. This storage stack is limited to ten new PRs after #371.

## Detached revision exports

`exportFullTrie` exports against the empty base. `exportTrieChanges(base, target, limits)` emits
only physical records absent from the declared complete base. Unchanged subtrees are skipped by
cached complete digest, including leaves moved by singleton collapse. Children precede parents.
The detached record includes full left/right child identities: JAM B intentionally clears the left
child's high bit, so its protocol bytes alone cannot serve as a physical navigation record.

Preflight bounds descriptor count and copied leaf bytes before allocation. No hashes or filesystem
operations occur. Result metadata copies base/target roots and exact target entry/node counts;
raw mutable transport records are untrusted and confer no chain authority. Leaf bytes are copied,
and no canonical ARC graph survives in the export. Empty/equal revisions may export zero records.

`make unit SUITE=storage_node_export` checks full/delta shapes, cached collapse, all output ceilings,
input/output isolation, zero crypto calls under refusal and 1,000 scoped ARC cycles. Future layers
must validate physical records before accepting them into a repository or disk layout.
