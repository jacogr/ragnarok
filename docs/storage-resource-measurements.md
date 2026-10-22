# Storage resource measurements

These optional synthetic panels help choose larger-state experiments before changing physical
storage layout. Memory/default journal behavior, managed layout, bounded history, finality,
recovery and independent checkpoint-import authority retain their existing contracts.

## Run the appropriate panel

| Make target | Observation | Important boundary |
| --- | --- | --- |
| `bench-storage-resources` | Whole-native-process peak RSS and minor/major faults | Includes fixture preparation, expected maps and all validation |
| `bench-storage-allocations` | Current Nim allocator bytes at lifecycle checkpoints | Fixtures and readers remain live where explicitly shown |
| `bench-storage-lifetimes` | Isolated fixture, owner, snapshot, copied-map/record and selection lifetimes | Fixture/validation scopes retire before owner sampling; final ARC release is asserted |
| `bench-storage-deployment` | 32,768/65,536/131,072-entry distinct-value trajectories | Bounded synthetic state with 16/64 publications, not production-scale throughput |
| `bench-storage-fresh-reopen` | Fresh native consumer RSS/faults and live allocator boundaries | Producer construction is excluded; kernel/page cache remains alive |
| `bench-storage-file-cache` | Complete read-only 16/64 MiB scans with unchanged/per-file advice | Logical reads, not device I/O; advice does not prove eviction |

Make provisions the pinned checked native ARC/Clang release/LTO profile where native code is used.
The file-cache panel uses fresh Python readers and therefore reports Python process resources,
including startup. Each panel owns its `build/tests/storage-*` results, Markdown, logs and any CSV.
A failed build, native assertion, timeout, malformed row, changed input or late artifact write
fails the panel and retires stale successful summaries. Prior evidence directories remain intact.

The existing Perf Storage job runs these beside its original speed panel. Resource observations
never become speed samples. Setup-free `make summary-storage-resources SUMMARY_OUTPUT=...` appends
independently validated resource status after the speed summary and fails missing/refused reports.
CI artifacts retain the complete raw observations and source/build/host identities.

## Interpret lifetime boundaries

The pinned Nim allocator reports current managed heap bytes. It excludes stack data, native-library
buffers, allocator reservation outside live allocations and OS page cache. Whole-child peak RSS is
a different process-lifetime observation and must not be subtracted between independent processes.

The isolated `owner` scenario retires prepared fixture graphs before sampling the complete physical
repository. Validation views also retire before close is measured. A retained immutable snapshot
or selected-root plan intentionally keeps that admitted graph alive after the mutable owner closes.
The 4,096-snapshot scenario measures its handle vector while sharing the graph; it does not duplicate
4096 physical maps. Complete-map extraction and physical record lookup return independently owned
payloads, checked again after the source owner closes. Every isolated scope must return to its
starting allocator baseline after its final owning object retires.

`lifetimes.csv` includes every checkpoint and explicit `-1` unavailable stage. Diagnostics subtract
only a stable baseline from the same native process, preserving unavailable stages separately from
an observed zero increment. Normalized larger-map occupancy uses matching 16-publication trajectories
and the same backend/order 32,768-entry anchor. Finite observations do not prove asymptotic behavior.

## Cache, restart and filesystem evidence

Native fresh-process reopen checks the exact successful producer root and local generation, every
independently expected key/value, retained views after owner close and unchanged selected file bytes.
Parent-side byte hashing and producer writes can populate the kernel cache. Fresh process does not
mean cold disk, and local restart never supplies independent checkpoint-import authority.

The file-cache panel creates and synchronizes exclusive synthetic files in its parent before fresh
read-only consumers start. Linux `POSIX_FADV_DONTNEED` or Darwin `F_NOCACHE` requests affect only
an owned descriptor/file. Their receipts distinguish requested, unsupported and refused. A request
is not proof of eviction or actual device reads. Read-interval page faults include advice, hashing
and complete byte validation; process peak RSS includes reader startup. There is no global cache
drop, production fault hook, file mutation or hardware power-loss simulation.

Environment records include filesystem geometry/capacity, numeric device identity, physical RAM
where observable, inherited memory limits and explicit cache policy. A recorded limit does not
assert enforcement. These bounded fixtures do not establish out-of-core behavior merely because
they are larger than earlier tests. [Child-local address-space ceilings](storage-memory-ceilings.md) now provide bounded allocation
experiments with fresh native controls. Controlled resident-memory pressure, page packing and
physical-device or filesystem power-loss qualification remain separately scoped work.

## Compare matching evidence

Clean-source resource reports can be compared after reviewing every allowed source difference:

```sh
python3 tools/compare_storage_resource_panels.py \
  --panel lifetimes \
  --baseline build/baseline/storage-lifetimes/results.json \
  --candidate build/tests/storage-lifetimes/results.json \
  --allow-source src/storage/node_repository.nim \
  --output build/storage-lifetime-comparison.md

python3 tools/storage_resource_diagnostics.py \
  --lifetimes build/tests/storage-lifetimes/results.json \
  --deployment build/tests/storage-deployment/results.json \
  --output build/storage-resource-diagnostics.md
```

Comparisons reparse native witnesses/commands and require matching cases, checked toolchain/native
providers, observer interpreter, host/environment and deterministic physical work. Source-inventory
changes require a new matching baseline. Peak ratios are descriptive candidate/baseline values,
not speedups or causal component estimates. Native panel schema 3 and fresh/file-cache schema 2
retain strict provenance; historical reports remain evidence for their original sources/schemas.

See the [measurement contract](../spec/storage-resource-measurements.md),
[larger-fixture contract](../spec/storage-deployment-benchmark.md),
[speed comparison guide](storage-performance.md) and [managed operator guide](managed-storage.md).
This work adds no M1 completion claim; complete protocol state serialization remains separate.
