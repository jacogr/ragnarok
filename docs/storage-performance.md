# Storage performance

`Perf Storage` is grouped beside `Perf PVM` in CI. Both storage panels and independent SDK controls
run in that one job, using pinned checked Nimony ARC/Clang release optimization with LTO:

```sh
make bench-storage
make summary-storage-benchmark SUMMARY_OUTPUT=build/storage-summary.md
```

Make owns setup and compilation. A failed build, assertion, IO operation, timeout, missing sample,
invalid provenance or late artifact write fails the job. The setup-free summary command refuses
incomplete reports. No performance threshold changes correctness or durability requirements.

## Matching workloads

| Panel | Configurations | Timed operations |
| --- | --- | --- |
| Short | 1,024/8,192 entries; leading/trailing keys; 16/256-byte values; sixteen one/four-key publications | Publication, warm reads/misses, snapshots, map extraction, strict reopen, nine-root/current reclamation |
| Sustained | 1,024/8,192 entries; hot/sweep updates; 64/256 four-key publications; 256-byte values | Publication, snapshots, spread resident reads and extraction before/after reclamation, strict reopen at each managed stage, nine-root/current reclamation |
| Larger sustained | 32,768 entries; sweep updates; 64/256 four-key publications; 256-byte values | Same sustained operations; the largest matrix is deliberately bounded |

Each complete configuration has three validated warmups and ten measured samples per pass. A second
pass reverses backend order. Fixtures and Merklization are prepared outside timing; returned values,
complete maps, roots and local generations are checked afterward. Warmups remain downloadable and
are excluded from statistics. Full revision bytes distinguish generation 256 from the seed.

Hot updates revisit 256 keys; sweeps advance across the map. At 64 publications both issue identical
writes, providing a physical-work control. Nine-root reclamation retains the seed plus the final
eight revisions, followed by a separate current-only phase. Every retained historical map is checked
after strict managed restart. Acquired views remain readable after compaction and native owner close.

These are synthetic physical repository operations. They do not execute blocks or establish complete
protocol state serialization, block finality, checkpoint authority or production throughput.

## Durability and resident reads

Memory publication has process lifetime only. Journal and managed publication include real
synchronization. Strict reopen includes selected-file admission, exclusive leasing and confirmation
syncs; it leaves data and namespace contents unchanged. Managed replacement includes file/directory
barriers, CURRENT replacement and predecessor retirement. Cleanup remains outside timed fixtures.

Disk-backed repositories keep resident immutable views. Read, miss, snapshot and extraction phases
measure those views and owned return values. They do not evict the OS cache or measure cold/random
disk access. A physical-address miss is not a protocol-key absence proof. Memory reopen, journal
reclamation and unsupported post-reclamation phases are explicitly unavailable.

The managed physical format, backend defaults and independent recovery/checkpoint trust contracts
remain unchanged. The private search directory accelerates full-address search without skipping
complete graph validation. It derives bounded 4/8/12-bit intervals from each immutable inventory.
Traversal scratch uses packed membership words; neither structure is serialized.

## Interpret the summary

Operation tables show median and min–max microseconds per fixed batch. Ratios compare matching
work; durable disk publication and memory publication have different guarantees. A dagger marks
absolute pass-median drift above 25% or central spread above 2×. A double dagger marks opposite-order
ratio drift above 25%. Pooling can conceal order effects, and stable ratios can coexist with noisy
absolute times. There is no universal speed threshold.

The sustained latency table adds batch-normalized mean call cost and writes/s, plus per-call p50,
nearest-rank p95 and maximum. Calls within a run are correlated, not independent trials. Batch
normalization includes loop/clock overhead. Opposite-order p95 drift is marked separately.

Growth curves divide the 256/64 batch-median ratio by four to compare average cost per publication.
Physical tables report record inventories and selected snapshot/journal extents before reclamation,
after nine-root replacement and after current-only replacement. Selected-file growth per authored
value byte is not device write amplification, allocated blocks, total directory usage or memory
retained by readers. Unknown or unsupported metrics never receive invented values.

A separate checked observer build emits SDK counts and discards instrumented timings. Resident
operations must have zero observed SDK calls. Strict reopen requires read/lease/confirmation-sync
witnesses without data/namespace mutation; managed compaction requires replacement and retirement
witnesses. Counts cover eight named SDK call sites, including attempts, rather than all OS activity,
bytes transferred or storage-device operations.

## Artifacts and reproducibility

`build/tests/storage-benchmark` owns:

- `results.json`, `samples.csv`, `summary.md` and logs for the complete job and short panel.
- `growth/results.json`, `growth/samples.csv` and `growth/publications.csv` for sustained raw data.
- `growth/io/results.json`, `growth/io/calls.csv` and logs for independent SDK evidence.

CI retains these alongside its Markdown summary. Source hashes, exact revision/dirty state, pinned
toolchain, Clang/CPU/platform/load, compiler and executable hashes, primitive bridge/provider closure
and observed object identity are recorded. Successful publication rechecks source inventories,
Git/compiler/Clang identity, native components and executables. Provider copies must be identical.
Source drift fails the job; timestamp-only changes preserve identical-content evidence.

Native command provenance requires the checked ARC/Clang release/LTO plan and binds every measured
case to the built executable and exact 13-sample arguments. An unchecked or observed profile cannot
supply speed samples. Raw statistics are recomputed before successful rendering.

Compare complete clean-source reports with explicitly reviewed source differences:

```sh
python3 tools/compare_storage_benchmarks.py \
  --baseline build/evidence-storage-growth-pre-index/results.json \
  --candidate build/tests/storage-benchmark/results.json \
  --allow-source src/storage/node_repository.nim \
  --allow-source tools/storage_growth_report.py \
  --output build/storage-comparison.md
```

The comparator refuses mismatched workloads, primitive/compiler/profile/host metadata, physical
counters or observed SDK work. Review every allowed source difference; changed fixtures require a
new matching baseline. Separate interleaved executable A/B measurements support attribution. One
comparison shortcut was rejected because its opposite execution orders disagreed, despite an
apparent pooled benefit. Historical artifacts apply to their recorded inputs only.

Local macOS ARM64 evidence does not assert Linux Actions results. Shared-host observations have no
frequency/affinity isolation. Process restart tests leave the kernel/page cache alive; hardware,
filesystem and device power-loss qualification needs a separately scoped environment. See the
[measurement contract](../spec/storage-growth-benchmark.md), [short-panel contract](../spec/storage-benchmark.md),
[managed operations](managed-storage.md) and [checkpoint trust](checkpoint-import.md).
