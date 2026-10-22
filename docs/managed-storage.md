# Managed disk storage

Memory remains the default backend. Disk mode defaults to the existing single-file `journal`
layout. Opt into a managed directory by appending these controls to normal command arguments:

```text
--with-state --chain chain.json --state-storage disk --state-layout managed --state-db ./state-managed
```

The parent directory must exist; a new database directory is created exclusively. It owns a stable
LOCK file, CURRENT manifest and numbered snapshot/journal pairs. Do not rename or replace its
namespace while a process owns it. A competing process, symlink alias, wrong chain/profile/schema,
corrupt selected snapshot or incomplete journal causes startup to refuse. Startup never scans for
another head, resets existing data, switches layouts or repairs an interrupted tail.

## Restart and checkpoint trust

Restart with the same chain, backend, layout and database path. A normal restart resumes its own
validated durable head with up to eight retained blocks plus any separated explicitly finalized
block. Persisting a block never finalizes it. Selected history and every retained complete map are
checked before listeners start. Retained immutable readers survive later publication, compaction
and explicit owner close.

[Checkpoint imports](checkpoint-import.md) still require independently trusted identity and exact
sealed header controls, and an absent destination. Imported checkpoints start with one retained
head and finality unset. Local restart and migration do not supply this external trust.

## Migrating a legacy single-file database

Stop the source node and choose a different, absent destination. Add these controls to normal
command arguments, preserving the configured chain and desired state mutation budgets:

```text
--with-state --chain chain.json --state-storage disk --state-layout managed --state-db ./state-managed --state-migrate-from ./state.db
```

The source is locked and fully validated as a local legacy database before copying its exact
selected generation, context, bounded history and explicit finality. The source file remains
byte-identical and independently usable. The destination must be absent; migration refuses an
existing destination and never performs an in-place conversion. Filesystem aliases cannot bypass
exclusive destination creation. Checkpoint import controls and migration cannot be combined.

On subsequent managed restarts, omit `--state-migrate-from`. A valid destination can remain after
an error later in startup; inspect it and use ordinary strict managed restart rather than retrying
migration over it. The explicit storage recovery APIs still require an exact independent prefix
generation/root token and may discard only an incomplete final append. There is no repair CLI.

## Reclamation policy and failures

`--state-compact-bytes` defaults to 67,108,864 bytes (64 MiB) in managed mode. It accepts 0 through
134,217,728 bytes (128 MiB). Zero disables automatic compaction and startup staging cleanup; it is
useful for inspecting preserved forensic files. Layout and maintenance controls require disk mode,
and the compaction control requires managed layout. Mutation defaults remain 1,000 writes and
100,000 written value bytes per batch, independently overridable, with explicit zero honored.

When the selected journal reaches the threshold beyond its fixed header, compaction retains the
exact canonical rolling history plus explicit finalized root, writes a complete snapshot and empty
journal, and durably switches CURRENT before retiring the previous pair. The state root, public
snapshot identity, generation and chain context do not change. A header-only journal does not
cause repeated compaction even with a threshold of one byte.

Normal publication and maintenance share one native worker. RPC stays paused and canonical graph
aliases remain frozen until the worker is collected or joined. Dispatcher ticks remain nonblocking.
Due maintenance runs after confirmed publication and before the producer receives its result;
startup performs due maintenance before listeners and workers start.

With automatic maintenance enabled, startup first validates the selected physical head and
canonical history, then removes only CURRENT.next, the immediate unselected successor pair and
the immediate predecessor pair. It never scans a directory or removes arbitrary older/future
files. Symlinks and nonregular files are refused. Failed live replacement keeps its actual receipt
and staged files for inspection rather than silently deleting a collision and retrying.

A maintenance failure preserves any already confirmed child and disables further mutation in that
Services lifetime. Download commands report `StorageMaintenanceFailure` with the actual confirmed
adopted count, including a child confirmed during joined shutdown. Fresh startup is required.
An uncertain ordinary publication remains uncounted unless durable completion and canonical
installation are confirmed. Failure after CURRENT replacement can leave the new physical epoch
selected; its receipt and strict reopen determine the result. Cleanup failure never implies rollback.

## Bounds and evidence

Managed mode inherits the existing graph and physical budgets: 4,194,304 physical records,
128 MiB physical value bytes, 64 MiB encoded batch, 4 MiB application context, and 256 MiB ceilings
for each selected snapshot and journal. Reclamation retains at most nine distinct roots. These
finite ceilings remain separate from protocol rules and caller mutation budgets. Selected-file
usage excludes staged/retired files and memory held by readers; unknown files can still consume disk.

The [integration contract](../spec/managed-disk-integration.md) records native lifecycle, recovery,
full-map/history/finality, real authenticated TLS migration/download, worker/RPC exclusion and
failure evidence. Synthetic compaction measurements use 64 sparse updates, nine retained roots
and ten samples each at 128 and 1,024 entries. Reusing already validated immutable selections
reduced compaction hashes from 1,530 to 511 and from 6,897 to 2,300; persisted bytes and strict
restart verification were unchanged. These local measurements make no general throughput claim.

Power-loss certification, production-scale layout tuning, page packing, disk caches and light-state
proof storage require further work. The application execution checks cover the implemented signed
execution path; they do not establish complete protocol state-transition parity.

## Performance comparison

The grouped Perf Storage job compares memory, synchronized journal and managed storage on fixed
checked workloads. The [performance guide](storage-performance.md) distinguishes resident reads,
durable publication, strict restart, bounded-history reclamation and selected-file extents. Its
host-specific measurements never replace recovery authority or independent checkpoint trust.

## I/O failure and restart guide

The [I/O failure guide](storage-io-failures.md) maps actual syscall boundaries to ownership,
uncertainty and explicit restart/cleanup behavior. It records the native refusal matrices and
keeps storage receipts separate from the stricter Services maintenance-failure policy.

## Process interruption and restart

The [process-crash guide](storage-process-crashes.md) explains strict restart, visible-but-unreturned
work, exact independent repair tokens, source-preserving migration and bounded cleanup after a
writer dies. Its native qualification covers actual process termination; hardware power-loss
certification and production-scale layout performance require separate evidence.

For live-owner/read-view retention, larger synthetic fixtures and fresh-process restart resource
observations, see the [resource measurement guide](storage-resource-measurements.md). Its explicit
cache-advice receipts do not establish cold storage, device I/O or hardware power-loss durability.
