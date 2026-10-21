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

## Durable StateStore owner

`state/disk_store.nim` owns one explicit-close, noncopyable `FileRepository` and an ordinary
in-memory `StateStore`. Creation requires an explicit complete snapshot and exclusively creates
the journal. Strict reopen requires independently supplied chain, root and exact local generation,
then constructs one StateStore from checked reachable leaves under explicit caller-selected policy.
No self-authentication, implicit repair, truncation, default database or policy widening occurs.

Updates fork the current immutable snapshot privately, validate/apply the borrowed batch, export
only changed physical nodes, and append/synchronize the journal before replacing the live memory
snapshot. Empty batches retain identity without a frame. Successful nonempty no-ops publish a new
snapshot and a journal generation. Native IO uncertainty poisons the journal: new reads/writes
refuse until close and explicit trusted recovery; already retained snapshots remain readable.
Failed initialization/open releases its lock, preserving any created bytes for explicit diagnosis.
Normal forks remain independent in-memory execution branches, never duplicate descriptor owners.

This first owner exposes durable state revisions only. It is not yet wired into normal application
adoption, canonical block metadata or a startup flag. Those require atomic publication of the
matching application context and coordination with state #5's startup/recovery layer. A successful
storage receipt cannot silently advance the application head or choose consensus authority.

## Publication failures and explicit recovery

`recoverDiskStateStore` wraps the existing independently trusted prefix repair; ordinary open
never repairs. Tests constrain actual child-process writes with `RLIMIT_FSIZE`: zero bytes, one
byte, half a frame and one byte short must fail; exact and ample ceilings are genuine controls.
Poisoned owners refuse new reads, updates and synchronization while held values remain readable.
Strict open preserves incomplete bytes. Wrong trusted generations preserve every byte. Authorized
repair restores the exact complete prefix, permits resumed append, and refuses complete visible
successors or complete checksum corruption. Repair may already be durable if subsequent policy or
cryptographic StateStore restoration fails; no writable owner escapes that later failure.

A separate maintained-crypto-observer suite refuses each required hash stage before update
publication. Every refusal preserves journal bytes, generation and exact old snapshot identity;
the same workload also completes with real successful controls.
