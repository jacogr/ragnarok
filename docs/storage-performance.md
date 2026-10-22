# Storage performance

`Perf Storage` stays beside `Perf PVM` in CI. Run the same checked workload locally:

```sh
make bench-storage
make summary-storage-benchmark SUMMARY_OUTPUT=build/storage-summary.md
```

Make owns pinned setup and native compilation. The benchmark uses checked Nimony ARC/Clang release
optimization with LTO. `build/tests/storage-benchmark` contains `summary.md`, `results.json`,
`samples.csv`, the native executable and build/process logs. CI retains these artifacts separately
from its Markdown job summary. A failed or incomplete run cannot publish a successful comparison.

## Compare matching workloads

| Dimension | Fixed alternatives |
| --- | --- |
| Backend | Memory repository, synchronized single-file journal, managed directory |
| Entries | 1,024 or 8,192 complete key/value entries |
| Keys | Leading or trailing two-byte identities; trailing keys add 232 shared prefix bits |
| Value bytes | 16-byte inline or 256-byte out-of-line payloads |
| Publication width | Sixteen batches of one or four writes, changing sixteen or sixty-four keys |

Every case has three validated warmups and ten measured samples. A second pass reverses backend
order: twenty measured samples per complete configuration, 1,248 raw observations including
warmups and 960 measured observations overall. These are synthetic physical-repository operations,
not block execution or complete protocol state serialization. Preparation and Merklization stay
outside timed publication.

## Read each operation separately

| Operation | Timed work |
| --- | --- |
| Publication | Sixteen public snapshot/publish calls; disk includes actual synchronization |
| Warm-view reads | 4,096 successful physical-leaf lookups and returned record ownership |
| Missing-address lookups | 4,096 typed refusals for a reserved zero physical identity |
| Complete-map extraction | Restore the complete selected key/value map |
| Retained snapshots | Acquire 4,096 immutable public snapshots |
| Strict disk reopen | Validate the selected snapshot/journal and every admitted revision |
| Nine-root reclamation | Select and clone memory records, or durably replace a managed epoch |
| Current-root reclamation | Reclaim the same nine-root union down to its selected current root |

Timed read payloads, extracted maps and generation/root identities are checked outside timing. Held
views survive reclamation, strict restart and native owner close. The nine-root phase checks every
historical map after managed restart; those synthetic revisions grant no block finality or trust.

Strict reopen is measured before compaction. Nine-root reclamation precedes current-only
reclamation. Managed replacement includes its file/directory barriers and old-pair retirement;
fixture cleanup is outside timing. Memory reclamation creates an independent private clone and
makes no durability promise. Memory reopen and journal reclamation are explicitly unavailable.

Reads, misses, snapshot acquisition and extraction use resident repository views for every backend.
They do not measure cold/random disk access or evict the OS cache. A physical-address miss is not
a protocol-key absence proof. Compare equal entries, key topology, value size and batch width.

## Interpret timings and physical evidence

Timing cells show microseconds per fixed batch: median and min–max. Ratios compare those batch
medians; memory publication is not interchangeable with durable disk publication. There is no
fixed speed threshold. A dagger marks absolute timings whose pass medians differ by more than 25%
or whose central sample spread exceeds 2×. A double dagger marks within-pass backend/memory
ratios that differ by more than 25% across reversed orders. Pooling can hide order or host effects;
common host drift can also leave a ratio stable while absolute timings are noisy.

The physical table reports stored/current record counts and selected snapshot/journal bytes
before and after reclamation. These exclude unknown/staged files and graph memory held by readers;
they are not total directory usage or resident memory. Identical fixture repetitions must retain
identical physical counters. Unknown or unsupported file metrics never acquire invented values.

The report records the source revision and dirty state, source hashes, pinned toolchain, compiler,
native executable and crypto ABI hashes, checked profile, CPU/platform and load. Successful
summaries require complete typed provenance and raw-derived statistics. CSV and Markdown are
published before the final successful JSON status; late artifact failures retain a failed summary.
Historical local artifacts remain evidence for their own recorded source/profile, not a later tree.

Local macOS ARM64 results do not assert Linux Actions results. Shared-host measurements have no
frequency/affinity isolation and do not certify production throughput, power loss, filesystem
behavior or long-running growth. See the [feature contract](../spec/storage-benchmark.md) for
verification and [managed storage](managed-storage.md) for operational behavior and recovery.
[Checkpoint imports](checkpoint-import.md) still require independent exact trust.

## Sustained publication panel

The same Perf Storage job now also runs 64/256 four-key publications against 1,024/8,192 entries,
using leading keys and 256-byte values. Each of its two opposite-order passes has three warmups
and ten measured samples. Publication, strict reopen, nine-root reclamation and current-only
reclamation stay separate. Every payload includes the complete revision number; generation256
cannot silently wrap to a seed value. Complete maps and held readers are checked outside timing.

The main Markdown summary includes this panel; `growth/results.json`, `growth/samples.csv` and
native logs retain its raw evidence beside the original short matrix. Parent source/compiler/
profile provenance explicitly covers both workloads. A failed or incomplete sustained panel fails
the entire job, even when the original short matrix passed. Selected bytes and physical nodes
exclude unknown files, filesystem allocation and memory held by readers. See the
[sustained workload contract](../spec/storage-growth-benchmark.md).

Per-call sustained timings are downloadable in `growth/publications.csv`, including exact revision,
sample, locality and warmup identity. Warmups remain raw evidence and never enter measured
statistics. A late failure publishing this file removes both child CSVs and refuses success.

The sustained latency table reports batch-derived mean call cost and writes/s beside individual
call p50, nearest-rank p95 and maximum. Warmups are excluded. Calls in the same run are correlated;
they are not additional independent trials. Opposite-order p95 drift is marked separately, and
normalized work includes the same loop/clock overhead in every backend. These are synthetic
four-key transactions, not block throughput, and memory remains non-durable.

The growth table compares 64 and 256 publications after dividing time by the fourfold change in
authored work. It shows added physical records and selected-file byte growth per authored value
byte. File growth is not device write amplification or filesystem allocation. Compare the same
entry count, update locality and backend; opposite-order uncertainty remains visible.
