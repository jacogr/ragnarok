# Memory and disk state storage

Memory is the default backend. To persist complete application state, append these controls to the
normal `server`, `client`, `mesh` or `download` command arguments:

```text
--with-state --chain chain.json --state-storage disk --state-db ./state.db
```

Omitted `--state-writes` and `--state-write-bytes` default independently to 1,000 writes and
100,000 written value bytes per batch. Either flag can override its default; explicit zero remains
zero. These are local resource policies, not protocol constants. The parent directory must already
exist. The default `journal` layout uses an exclusively locked regular file and refuses
symlinks, a competing owner, incompatible identity/schema and corrupt or incomplete journals.
Each file belongs to one configured genesis header, complete genesis state root and full parameter
profile. Memory/disk selection is independent of the future full/light node mode.

To run ephemerally, omit both backend controls or select `--state-storage memory` and omit
`--state-db`. A memory run does not alter or resume a previous disk database.

## Creation and local restart

A missing path is created exclusively from the configured complete genesis. A normal restart opens
its own validated durable head without external checkpoint files. Startup verifies chain identity,
journal integrity, complete reachable state graphs and the stored header/profile/state bindings.
It restores up to eight retained blocks and any explicitly selected finalized block, including an
older finalized anchor. No block becomes finalized merely because it was persisted or reopened.
RPC starts with this same restored history and exact current snapshot owner.

Invalid existing data never falls back to genesis or memory. Interrupted initialization keeps its
forensic bytes; bootstrap-only metadata cannot become a canonical head. Keep the database path and
parent directory stable while the process owns them.

## Importing an independently trusted checkpoint

The [checkpoint import controls](checkpoint-import.md) still require a checkpoint plus an independently
trusted identity and exact sealed header. Combine that complete request with disk mode only for a
**new** database path. The imported head starts with one retained block and finality unset; it does
not borrow local history or finality from another database. Any existing path causes import startup
to refuse without replacing its contents.

For later local restarts, omit the checkpoint/trust/header/import-byte controls and keep the same
chain/backend/layout/path and desired mutation budgets (defaults or overrides). Switching backend
does not migrate databases. The [managed layout](managed-storage.md) offers online reclamation and
explicit source-preserving migration from a legacy journal.

## Durable publication and shutdown

Queued adoption stages an immutable successor, then a native worker writes changed records and
matching chain context together. RPC is paused while the worker owns the shared graph lease. The
producer receives success only after the durable receipt and canonical/RPC installation agree.
Service and download ticks remain nonblocking during journal writes and synchronization.

A process exit after confirmed durability resumes the successor even if the previous host had not
collected its receipt or installed its in-memory head. Explicit shutdown joins native IO before
retiring execution inputs or canonical owners and preserves the actual receipt. Stopping a live
backend requires a fresh service startup before further mutations. Component callers use the
queued adoption API in disk mode; synchronous `Services.applyAccumulation` returns
`DurabilityRequired` rather than bypassing persistence.

A failed or uncertain write preserves the prior in-memory canonical owner and its held readers,
retains the typed IO outcome and prevents further writes in that lifetime. Strict restart refuses
an incomplete tail without modifying it. There is no automatic repair or repair CLI in this tranche.
The explicit storage recovery API requires the exact independently retained previous generation/root;
it can discard only an incomplete final append, never a complete successor or corrupt complete frame.

## Current bounds and remaining work

The initial backend caps the journal at 256 MiB, physical retained value bytes at 128 MiB, physical
records at 4,194,304, an encoded batch at 64 MiB and application context at 4 MiB. These are finite
implementation ceilings, separate from complete-map and caller-selected mutation budgets. All
physical history in the default `journal` layout is append-only; the eight-block application
window does not reclaim its node records. The opt-in [managed layout](managed-storage.md) reclaims
unreachable records while preserving the selected history and finality. Page packing, a disk cache
and automatic database migration remain outside this implementation.

Startup currently reconstructs the configured genesis and bounded historical maps. The existing
[storage measurements](../spec/disk-state-store.md) cover sparse publication, exact counters and
strict reopen, with explicit noise and workload limits. Production-scale layout, reclamation and
restart tuning need further measurements. Light-state proofs and databases remain separate work.

## Full paged layout

Select the full paged backend explicitly by appending:

```text
--with-state --chain chain.json --state-storage disk --state-layout paged --state-db ./full-paged
```

The selected directory contains a V2 immutable complete-state artifact and one atomic `CURRENT`.
Its authenticated context carries the same complete header/profile/history/finality bindings as
the other application backends, plus the exact previous selected manifest for explicit retirement. Startup restores every retained complete root before exposing the
canonical view. External checkpoint import keeps its independent trust/header checks and creates
exclusively; ordinary local restart preserves that imported head without requiring import files.
A different physical layout, chain, profile or corrupt selection fails without conversion or repair.
Managed migration and compaction flags are rejected for this layout.

Both application update families use the existing joined publication worker. The dispatcher reads
only the last confirmed owned state/context metadata; the excluded worker rechecks native selection,
authors the exact retained complete-root union, and confirms file/directory barriers before host
canonical/RPC adoption. Native uncertainty quarantines new owner reads until close/recovery while
already retained immutable snapshots remain readable. Paged artifact retirement and interrupted
candidate cleanup use their explicit native receipt/replay contracts; directory contents never
authorize inferred deletion.

Full paged application publication now automatically retires the exact authenticated predecessor
through the existing disk worker before another artifact can be authored. Foreign old-reader pins
produce bounded retry/backpressure; cleanup uncertainty stops later writes while preserving the
already confirmed canonical head. Restart retries the same descriptor, including synchronized
already-absent retirement. Cleanup receipts remain separate from publication receipts.

Use `--state-paged-resume` with explicit disk/paged storage to resume an interrupted paged
operation. It can complete a matching failed configured-genesis or trusted-checkpoint import
from the supplied independent inputs. For an existing head it waits for an independently
prepared matching update before clearing remnants and publishing once. Ordinary startup
preserves forensic files. The flag cannot replace an existing selected head through bootstrap
or repair a corrupt selected graph; after successful recovery ordinary startup is sufficient.
