# State storage direction

[Design overview](../design.md) · [Disk operation](../disk-storage.md) ·
[Storage source map](../../src/storage/README.md)

JAM commitment rules and physical storage layout evolve on separate axes.
Keys, node encodings and roots must remain exact. File offsets, indexes, page
packing and caches can change while preserving that commitment.

## Node modes and database selection

Startup selects the mode, chain identity and database location before opening storage.
Full databases own complete execution state. Light databases own authenticated partial
proofs and trusted headers. Incompatible identity or schema fails at open.
[Database identity](../../src/storage/database_identity.nim) ·
[Light runtime](../../src/app/light/runtime.nim)

## Shared disk and memory interface

Where semantics match, consumers use atomic batches, retained views and explicit
missing values across backends. Disk durability adds synchronization and restart
authority. A missing partial-cache entry remains unknown.
[Memory store](../../src/state/store.nim) · [Disk state owner](../../src/state/disk_store.nim)

## Key/value storage and Merkle state

The Merkle layer owns protocol layout and commitments. Physical repositories own
publication and recovery of selected roots and other records.
[State layout](../../src/codec/state/layout.nim) ·
[Managed repository](../../src/storage/managed/repository.nim)

## Ideas to study

[Firewood](https://github.com/ava-labs/firewood) offers revision sharing and reclamation
ideas. [NOMT](https://github.com/thrumdev/nomt/blob/master/docs/nomt_specification.md)
offers subtree locality. [ParityDB](https://github.com/paritytech/parity-db) illustrates
byte transactions with distinct visible and durable publication.

## Incremental implementation

Qualify each physical change against exact roots, retained readers, resource ceilings
and failed publication. Use real-file checks for durability and restart.

## Role of checkpoints

Full checkpoints support export/import and independent recovery checks. Historical
retention selects exact records separately from the live validation window.
[Checkpoint codec](../../src/state/checkpoint.nim) ·
[Retention evidence](../../spec/block-state-retention.md)
