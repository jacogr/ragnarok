# Correctness-validated PVM speed comparisons

## Authority and readiness

Gray Paper 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401` remains primary;
PolkaVM `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` is a test-only comparison.
The preceding register, control, memory, host, metered-retry and complete-program
corpora establish a useful common subset before timing. This is the first limited
baseline, not a declaration that all PVM/JAM correctness gates are closed.

One consolidated comparison covers all workloads and both reference backends. The
independent fixture generator encodes original guest bytes and derives complete
registers, memory, host-call counts and GP block prices without either engine
producing expectations. Five fixed guests exercise arithmetic/branches (10000 loop
iterations), scalar memory (1000 aligned/crossing iterations) and memory/host loops
(1000 aligned/crossing iterations). All use finite gas and local native step limits.

## Build and measurement contract

The native driver uses pinned Nimony 0.6.3 nightly
`5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`, ARC, Clang, LTO and checked release
with bounds/assertion contracts enabled. The optional reference crate uses pinned
Rust 1.99.0 and the exact upstream release profile: LTO, one codegen unit and debug
symbols. Its transitive versions/checksums match the pinned upstream lock. Default
PolkaVM features and public JamV1 APIs are used; no nightly musttail feature,
experimental sandbox, source patch or dependency upgrade is introduced.

Both reference backends use Sync/Full/L2Hit pricing. The requested backend is explicit;
an unavailable compiler/profile receives no timing and no interpreter substitution.
Engine setup failures, including unavailable dynamic-paging kernel facilities, are
reported per workload. Invalid modules, incorrect results or unsupported observed
exits fail the run rather than becoming an unavailable result. No kernel setting is
changed. Compiled CPU support/module checks still apply on an otherwise supported host.

The measured region is execution through final halt, including host dispatch/replies
where applicable and normal transient allocation/ARC work. Process startup, program
capture/module compilation, instance/input reset and complete result validation are
outside the execution timer. Native execution retains its immutable initial source;
reference execution starts from a newly initialized instance each sample. Both expose
equivalent complete final state. Preparation observations are retained separately;
their boundaries differ by runtime and they are not presented as comparable execution
measurements or a repeated compile-time benchmark.

Each pass performs three validated warmups and ten validated measured executions per
guest. Two passes reverse engine order. Every sample must match all thirteen registers,
remaining gas, host-call counts and every relevant memory byte before acceptance.
Native checks additionally preserve source aliases. No expected-value checks or
printing are in the timed region except the host dispatch/API contracts themselves.
The raw fixture has `PVMBEN01` framing, five 273-byte record headers and bounded blobs;
its descriptor pins exact SHA-256 bytes.

## Results and quality

`make bench-pvm` retains `build/tests/pvm-benchmark/results.json`, `samples.csv`,
`summary.md` and logs. The JSON includes all warmups/measured samples, per-pass medians,
spread/noise flags, one-time preparation observations, exact build commands, CPU/OS,
load averages, toolchain/compiler identities, source inventories, fixture hash and
recorded Git head/dirty status. An uncommitted local tree is identified by its source
hash inventory; its recorded parent head is not claimed as an exact clean revision.

No samples are discarded. A row is marked noisy if per-pass medians differ by more
than 25% or the central sample spread exceeds 2×. Those are diagnostic heuristics,
not confidence intervals or performance failure thresholds. All raw outliers remain
visible in the min/max and artifacts. Missing/duplicate samples, inconsistent backend
availability, malformed output, result mismatches or stale reports cannot become a
successful table. Failed runs replace old Markdown and clear stale CSV measurements.

Local baseline on 2026-10-21: Apple M1 Max, ten logical CPUs, macOS ARM64. These medians
are microseconds per complete fixed guest, measured with the final upstream release
profile. Full ranges and both passes are in the retained artifacts.

| Workload | Ragnarök PVM | PolkaVM interpreted | PolkaVM compiled |
| --- | ---: | ---: | --- |
| Arithmetic, 10000 iterations | 4931.67 | 97.81 | Unavailable on this platform |
| Memory aligned, 1000 iterations | 1468.40 | 16.44 | Unavailable on this platform |
| Memory crossing, 1000 iterations | 1611.73 | 40.29 | Unavailable on this platform |
| Host/memory aligned, 1000 iterations | 2065.50 | 48.79 | Unavailable on this platform |
| Host/memory crossing, 1000 iterations | 2254.31 | 72.96 | Unavailable on this platform |

The observed interpreter gap is about 31–89× for this subset. This identifies a
substantial performance gap, without attributing it to a specific function or
promising whole-client throughput. An earlier loaded-host run had severe spread;
its raw evidence is retained separately, and prompted the explicit noise flags.
There is no CPU affinity/frequency isolation, cache simulation or profiling result
here. Linux or compiled-backend performance does not follow from this local table.
No production optimization or weaker checking profile was used to obtain results.

## Actions delivery and reproduction

The canonical workflow has a separate manually selected `bench-pvm` scope, gated by
the compiled fixture comparisons. Dedicated hosted Linux jobs enable the pinned
upstream sandbox prerequisites and require actual compiled measurements. Local hosts
may still report unavailable; no local kernel settings are changed. See
[compiled CI](pvm-linux-compiled-ci.md). It is
excluded from normal unit/full/PR-label verification, and has its own inventory,
setup and strict execution verdict. Its Actions summary shows the consolidated table;
the artifact retains raw JSON/CSV, Markdown and build/run logs for thirty days.
The job never uploads executables or dependency trees. No remote run is implied by
adding the job.

```sh
make bench-pvm
make summary-pvm-benchmark SUMMARY_OUTPUT=build/pvm-speed-summary.md
gh workflow run ci.yml --ref <branch> -f suite=bench-pvm
```

Benchmark/oracle/lock/profile/report guards, existing CI/summary/Make safeguards,
inventory and both relevant pinned formatters pass locally. Real native and reference
controls reject tampered expected results and block prices before accepting a sample.
The future full upstream fuzzing/differential CI obligation remains separate.
