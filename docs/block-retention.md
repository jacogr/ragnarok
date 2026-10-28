# Historical blocks and complete states

Full nodes keep the latest eight accepted blocks and their corresponding complete states by default.
Select another window or keep every future accepted block:

```text
--with-state --chain chain.json --retain-blocks 300
--with-state --chain chain.json --archive
--with-state --chain chain.json --retain-blocks -1
```

`--archive` and `--retain-blocks -1` select the same policy. Counts are positive unsigned 64-bit
decimals; zero, other negative values, overflow, repeated selectors and combining the flags are
errors. The window includes the current head. Slot gaps consume no extra entries. A configured
genesis/checkpoint seed counts as one available entry; it does not imply earlier data exists.
Only accepted direct children of the selected linear chain are recorded. Rejected traffic,
duplicates, forks and transport framing are excluded; no fork-choice or reorganization archive
is implemented. Protocol recent-history state, root computation and execution rules are unchanged.

These flags select local history independently of memory/disk and journal/managed/paged layout.
They require full-state activation and are rejected in light mode. Memory history disappears when
the process exits; a memory archive grows with the retained data. The immutable hash index bounds
lookup depth and avoids copying an archive-length list on advance. Disk archives use fixed cursor
metadata and disk hash/ordinal indexes; only the requested complete record is decoded for a lookup.
Opening validates the selected index suffix with constant working memory, so startup time grows
with retained entries.

## Current state, validation and finality

Complete current state always remains available. An explicitly selected finalized snapshot remains
available even outside the requested window. A separate cache retains at most eight linked headers
for existing validation inputs, without retaining their complete states or bodies. It does not widen
the requested complete-state window. No persisted block becomes finalized merely by being reopened.

Disk storage keeps at most `min(N, 8)` full states in the live view, or eight for archive mode, plus
any separate finality anchor. Other selected historical states live in independent complete records.
Managed/paged live-root limits therefore do not cap archive length. The existing public RPC exposes
the live view and explicit finality; archive disk reads use the offline command/library below.
Synchronous historical IO must run during startup/offline work or under an excluded storage owner,
never in a network dispatcher callback. Reads are refused while Services has a graph lease active.

## Restart, migration and pruning

An explicit flag atomically publishes a new disk retention policy before listeners start. An indexed
database reopened without either flag preserves its stored policy, including archive mode. A fresh
or legacy database with no flag retains the default inline eight-entry history. V1/V2 contexts remain
readable; new publications use V3 live metadata and, when indexing is enabled, a fixed-size selected
cursor. Older binaries cannot open these newer formats.

Enabling an index migrates only the available inline snapshots. Legacy/checkpoint seeds may have
complete states and sealed headers without complete raw bodies. Those bodies remain unavailable.
Shrinking deletes excluded history after the new cursor is confirmed durable. Expanding or switching
to archive preserves the oldest available floor and records future accepted children; it never restores
deleted history. Earlier data requires an independently trusted backfill/replay source; automatic
backfill is not provided. Journal-to-managed migration copies the selected archive before selecting
the fresh destination and refuses an existing historical catalog.

Historical files live beside the primary database at `DATABASE.history`. Keep that directory together
with the database when moving or backing it up, with the writer stopped. Records and indexes are
synced before canonical publication; orphan future files cannot become queryable without the selected
cursor. Unselected forensic files from failed attempts can remain and consume additional disk.
Pruning acknowledges durable progress separately and retries after interruption. Cleanup
failure is reported without revoking an already confirmed block. Loaded complete state/body readers
remain valid after pruning, compaction and database close; passive cursor metadata alone does not
pin files. Existing native paged-reader pins retain their independent retirement contract.

The initial disk layout stores a complete checkpoint per accepted block, plus exact block bytes and
index metadata. It does not deduplicate states across records: archive disk usage can grow rapidly.
Each record/export has a 16 MiB ceiling, independently of retained entry count; existing physical,
context and mutation budgets also apply. Storage limits and IO failures are explicit refusals rather
than incomplete historical records. Future deduplication requires separate layout/recovery work.

## Offline queries

Stop the running writer first: queries use the ordinary exclusive database lease. Select an exact
64-digit lowercase header hash or a positive local acceptance ordinal:

```sh
ragnarok history --with-state --chain chain.json \
  --state-storage disk --state-db ./state.db --state-layout managed \
  --history-block HASH --history-checkpoint ./historical.checkpoint

ragnarok history --with-state --chain chain.json \
  --state-storage disk --state-db ./state.db --state-layout managed \
  --history-ordinal 42
```

The command prints JSON containing `blockHash`, `stateRoot`, `slot`, `stateEntries`, `headerHex`,
`bodyAvailable` and `blockHex`. Block/header hex is exact, without transport framing. Old header-only
seeds return `bodyAvailable: false` and `blockHex: null`; their complete state is still exportable.
`--history-checkpoint FILE` optionally writes the selected complete application checkpoint atomically,
using the existing checkpoint format. `headerHex` supplies its exact sealed header for independent
inspection/trusted import. Preserve independent trust when importing a checkpoint.

Ordinals count local accepted entries from the available seed, not global block height or slot.
An ordinal below the stored floor reports `Pruned`; a future ordinal or unknown/reclaimed hash reports
`Unavailable`. Hash aliases are reclaimed without permanent tombstones, so an unknown hash cannot
always be distinguished from a pruned one. Missing/corrupt selected data reports its typed failure.
The command exits nonzero for failures, never creates a missing database, never substitutes current
state/genesis, and accepts no listener, recovery, migration or retention-changing controls. Use the same
chain, explicit disk layout and mutation budgets as normal startup. Hash queries work on legacy inline
windows too; ordinal addressing requires an enabled disk index.

The library exposes `Services.historicalSnapshot(hash)` for full memory/disk owners and
`Services.historicalSnapshot(ordinal)` for indexed disk owners. Success returns an independently owned
application chain containing the exact selected full state and block/body availability. Finalized hash
queries remain available outside the user window. [The feature contract](../spec/block-state-retention.md)
records durable ordering, formats and verification evidence.
