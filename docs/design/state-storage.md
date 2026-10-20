# State storage direction

Status: design note for discussion; no backend or dependency has been selected.

Ragnarök should grow a small Merkle-aware storage implementation as concrete needs arise.
Firewood, NOMT and ParityDB are useful design references. Adopting an existing engine remains
an option; none is a dependency requirement. A generic transactional key/value database is also an option,
not an architectural prerequisite.

The boundary to preserve is **JAM's commitment rules versus our physical storage layout**.
Protocol keys, node encodings and root computation must remain exact. File offsets, indexes,
page packing and caches can evolve independently while producing the same protocol root.

## Node modes and database selection

Full and light nodes are required operating modes. A startup flag selects the mode and opens its
corresponding database. Each mode has a separate database identity and schema: complete execution
state for full nodes, and authenticated partial state/proofs and trusted commitments for light
nodes. Shared storage operations do not imply identical state semantics. A partial mapping must
never be presented as a complete state root.

Database location is configurable. Provide a predictable default location, with full and light
stores separated, and a path override so multiple independent databases can coexist on one host.
Resolve the selected mode, chain identity and database location before opening storage. Persist
and validate database identity/schema metadata; incompatible mode, chain or format must fail
explicitly rather than silently reopening or converting another database. A mode switch selects
the corresponding store; it does not migrate full state into light state or vice versa.

The first implementation need not open multiple databases in one process or provide transactions
across independent databases. Exact flag spelling and default filesystem paths can be chosen when
startup configuration is implemented.

## Shared disk and memory interface

Support an in-memory database through the same storage interface used by the disk implementation.
This allows isolated tests and ephemeral runs to exercise normal storage consumers without
filesystem-specific branches or a separate mock-only execution path.

Define the shared contract around the operations actually needed: reads with explicit missing-key
semantics, atomic mutation batches, stable retained read views, and explicit open/close ownership.
Add iteration or further operations when a consumer requires them. Both implementations must agree
on visible batch atomicity, view lifetime, empty values, errors and resource limits.

Durability must remain explicit. An in-memory implementation retains data only for its lifetime;
it cannot establish survival across a process restart. A shared synchronization operation must
document that distinction. Tests for storage semantics should run against both implementations;
disk synchronization, crash recovery and publication failures need real-file tests.

Full and light state APIs may differ above this shared interface, particularly around proof-backed
reads and what an absent local entry means. An unproven missing light-state entry must not become
a claim of protocol-level absence.

## Key/value storage and Merkle state

Separate the responsibilities of storing bytes from maintaining authenticated state. The storage
contract owns addressing, reads, atomic batches and persistence. The Merkle layer owns JAM key/node
encodings, root computation, versioned state views and eventual proof operations. Block/head
metadata and other non-trie records also need storage without acquiring Merkle semantics.

This is a logical boundary, not a requirement to flatten every trie node into a generic KV engine.
A small KV implementation is a valid starting point; a specialized layout can later pack trie nodes
or address them directly if measured requirements justify it. The storage design must define how
new trie data and its selected root/head are published consistently, including any namespaces used
for non-trie metadata. An atomic batch becoming visible and becoming durable are distinct events.

## Ideas to study

- [Firewood](https://github.com/ava-labs/firewood): uses the trie directly as its on-disk index,
  addresses nodes by file offsets, shares nodes across revisions and reclaims space as retained
  revisions expire. Relevant lessons concern revision ownership, durable publication and safe
  reclamation.
- [NOMT](https://github.com/thrumdev/nomt/blob/master/docs/nomt_specification.md): groups binary
  subtrees into pages with identities derivable from key paths. Relevant lessons concern page
  locality and reducing dependent reads during traversal.

- [ParityDB](https://github.com/paritytech/parity-db): an embedded transactional key/value store
  optimized for blockchain workloads, with columns, atomic write batches and optional reference
  counting. It illustrates a byte-storage engine that can hold trie nodes alongside other record
  types while leaving protocol Merklization to its consumer. Its distinction between visible
  commits and persisted data is also relevant to our durability contract.

These are ideas to evaluate, not commitments to any project's trie format, hash conventions,
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

The first trie increment can cover complete full-node state while the shared storage contract
supports disk and memory implementations. Light-node storage remains a required separate mode;
its proof/trust contract must be designed before introducing light-state reads or persistence.

## Role of checkpoints

The current checkpoint stack provides complete-map serialization, checked restoration and durable
head-selected publication. Keep it as a recovery baseline, export/import path and cross-check for
future storage. Whole-map checkpoint writes need not become the normal per-block persistence path.

Before adopting a new storage increment, verify exact roots, retained historical views, bounded
resource use and failed-publication recovery. Durability and recovery tests should grow with each
new disk mutation boundary. Proof APIs, archival history and advanced I/O machinery should follow
actual requirements rather than being bundled into the first backend.
