# Standalone storage records

Scope: detached changed-node persistence foundations under `src/storage/`. GP 0.8.0
`07f041dabd073f9018b418e9ee72e79dd2185401` M/B/L remain authoritative; physical records
are local storage data. No state/checkpoint/PVM/application consumer may adopt this work until
explicitly authorized. This storage stack is limited to fifteen new PRs after #371.

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

## Strict physical batch codec

`record_codec.nim` encodes exact `RAGNAROK-TRIE-V1\n`, base/root (32 bytes each), uint64
little-endian target entry/node/record counts, then physical records. A leaf stores tag 0, digest,
31-byte key, uint64 raw length and raw value. A branch stores tag 1, digest and both 32-byte full
children. Unused raw object fields must be zero/empty; empty branches, duplicate addresses and
nonempty records at the reserved zero address reject. Root/count claims are bounded but not trusted.

Decode scans every extent and budget before allocating records. Both encode and decode verify
all local node digests through existing JAM B/L primitives; only complete success exposes payload.
Complete graph availability, key routing and externally trusted root selection are later repository
responsibilities. The codec does not authenticate a caller's root or a chain transition.

`make unit SUITE=storage_record_codec` verifies exact framing, every truncated prefix, trailers,
invalid tags, full-width length/count attacks, duplicate/canonical field refusal, changed value
integrity, exact/short encoded budgets and present/empty transport ownership.

## Atomic in-memory node repository

`node_repository.nim` publishes one complete root only after raw records pass local integrity and
full graph validation: all children exist, keys follow MSB routes, no node repeats/cycles, branches
contain at least two leaves, and exact entry/node/value budgets agree. Unreachable new records
refuse. Existing addresses may be reused only with identical physical records; the full left child
is part of physical identity even though JAM masks its high bit in B.

`publish(expectedView, batch)` requires the exact current view and matching base root. Generations
are local checked uint64 ordinals. Private candidates publish at one point; all refusals preserve
the previous view. New values are copied. Copies of the updateable owner branch independently,
and retained read views survive updates and explicit close. Missing physical records, default
views and present-empty leaves remain distinct. Accumulated node/value ceilings include old nodes;
no reclamation, disk durability or state-consumer integration is introduced here.

`make unit SUITE=storage_repository` checks independent changed-node publication, exact counts,
input/read isolation, stale/base/partial/misrouted/count-invalid refusal, storage budgets, close
lifetimes and 1,000 fresh ARC cycles. Shared storage samples remain test-only.
