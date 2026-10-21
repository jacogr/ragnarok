# Disk state storage

The maintainer authorized disk storage, including application backend selection, on 2026-10-21.
db #1 owns storage and StateStore persistence APIs; state #5 independently owns checkpoint recovery
and startup. GP 0.8.0 and existing compiler/crypto pins remain unchanged. Full/light mode and
memory/disk backend selection are independent. This feature does not implement partial light state.

## Snapshot transport

StateStore exports bounded full/delta physical records directly from its immutable cached trie.
Exports copy raw bytes, grant no authority over the source, and require no cryptographic work.
Default snapshots refuse export; limits preflight descriptor and payload allocation. A disk owner
must authorize exact snapshot identity before using a delta: equal roots alone grant no authority.
Repository restoration can extract detached complete leaves under an independently trusted root
without building an intermediate trie. This avoids reconstructing and hashing a second temporary
trie before constructing a StateStore. Returned leaves remain mutable transport values only.

## External design references

- [Firewood](https://github.com/ava-labs/firewood): physical addresses separate from Merkle hashes,
  explicit retained revisions, and data durability before root publication.
- [NOMT](https://github.com/thrumdev/nomt/blob/master/docs/nomt_specification.md): path-derived page
  identities and subtree packing reduce dependent reads.
- [ParityDB](https://github.com/paritytech/parity-db): atomic batches and distinct visible/durable
  stages, with OS page cache and separate metadata columns.

These sources inform design tradeoffs; no foreign node encoding, dependency or license-bearing
implementation is copied. Our journal remains the correctness baseline. Layout/cache/reclamation
changes require reproducible measurements and recovery tests; no throughput claim follows from
fewer encoded bytes alone. Canonical block authority cannot be inferred from a locally valid root.
