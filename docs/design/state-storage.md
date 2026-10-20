# State storage direction

Status: design note for discussion; no backend or dependency has been selected.

Ragnarök should grow a small Merkle-aware storage implementation as concrete needs arise.
Firewood and NOMT are useful design references. Adopting either remains an option, but neither
is a dependency requirement. A generic transactional key/value database is also an option,
not an architectural prerequisite.

The boundary to preserve is **JAM's commitment rules versus our physical storage layout**.
Protocol keys, node encodings and root computation must remain exact. File offsets, indexes,
page packing and caches can evolve independently while producing the same protocol root.

## Ideas to study

- [Firewood](https://github.com/ava-labs/firewood): uses the trie directly as its on-disk index,
  addresses nodes by file offsets, shares nodes across revisions and reclaims space as retained
  revisions expire. Relevant lessons concern revision ownership, durable publication and safe
  reclamation.
- [NOMT](https://github.com/thrumdev/nomt/blob/master/docs/nomt_specification.md): groups binary
  subtrees into pages with identities derivable from key paths. Relevant lessons concern page
  locality and reducing dependent reads during traversal.

These are ideas to evaluate, not commitments to either project's trie format, hash conventions,
file format or full feature set. JAM's own rules remain authoritative.

## Incremental implementation

1. **Incremental in-memory trie.** Update affected paths and share unchanged immutable nodes.
   Cross-check roots against the existing complete-map calculator, retaining it as an independent
   correctness reference.
2. **Persist changed nodes and values.** Start with a simple versioned layout. Make all data
   required by a selected root durable before publishing that root as the durable head. Reuse
   applicable ownership and publication primitives from the checkpoint work.
3. **Explicit revision retention.** Retain the roots needed by execution and bounded fork/reorg
   handling. Define when readers release a revision before introducing reclamation or space reuse.
4. **Measured storage improvements.** Add page packing, caching and allocation/reclamation
   machinery when observed workloads justify them. Each increment should satisfy a current need.

The initial scope is complete full-node state. Partial light-state storage and proof-backed reads
retain a separate contract; a partial mapping must never be presented as a complete state root.

## Role of checkpoints

The current checkpoint stack provides complete-map serialization, checked restoration and durable
head-selected publication. Keep it as a recovery baseline, export/import path and cross-check for
future storage. Whole-map checkpoint writes need not become the normal per-block persistence path.

Before adopting a new storage increment, verify exact roots, retained historical views, bounded
resource use and failed-publication recovery. Durability and recovery tests should grow with each
new disk mutation boundary. Proof APIs, archival history and advanced I/O machinery should follow
actual requirements rather than being bundled into the first backend.
