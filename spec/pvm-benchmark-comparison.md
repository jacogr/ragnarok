# Correctness-validated PVM speed comparisons

## Authority and readiness

Gray Paper 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401` remains primary;
PolkaVM `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` is a test-only comparison.
The preceding register, control, memory, host, metered-retry and complete-program
corpora establish a useful common subset before timing. This is the first limited
baseline, not a declaration that all PVM/JAM correctness gates are closed.

One consolidated comparison covers all workloads. The maintainer currently selects
Ragnarök versus the PolkaVM interpreter; compiled comparison is explicitly deferred
until the interpreter baseline is competitive. No compiler backend process is started
by `make bench-pvm`, and no CI kernel settings are changed. The
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

The reference interpreter uses Sync/Full/L2Hit pricing with an explicit backend.
Invalid modules, incorrect results or unsupported observed exits fail the run.
No compiler process or kernel configuration change is part of current measurements.
The retained Rust driver supports explicit compiler selection for future use; that
capability is not requested by the maintained baseline command.

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

The canonical workflow has a separate manually selected `bench-pvm` scope. It is
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

## Current comparison scope

On 2026-10-21 the maintainer requested keeping comparisons interpreted while Ragnarök
is substantially behind. Reports retain an explicit `Deferred` compiled column and
reason, with no timing samples or backend-availability claim for that column. Two
opposite-order passes measure only Ragnarök and the pinned PolkaVM interpreter.
Historical reports with unavailable/measured compiled entries remain readable; they
do not establish that the current command requested that backend.

The experimental hosted compiler correctness run found a pinned host-API panic when
seeding the last 4 KiB page. Its evidence is retained in the
[compiler boundary record](pvm-compiler-final-page.md). Compiled CI, sandbox kernel
changes and a required-compiler gate are deferred along with compiled performance.
The ordinary full reference job continues to check the interpreter/native pairs.

The interpreter-only command passes locally with all five validated workloads,
20 measured samples per active engine and explicit deferred compiler rows. All 51
selected tooling/CI/summary checks pass. Raw checks confirm no compiler command ran;
compiled rows carry no samples. Existing native code, workload inputs, pins and build
profiles are unchanged. These local results do not imply an exact-head Linux result.


## Invocation cursor optimization, 2026-10-23

A fresh checked baseline at `3240ebba` used the unchanged five-workload fixture, pinned
Nimony/Rust/PolkaVM, checked ARC/Clang LTO and the same Apple M1 Max host. macOS `sample`
on repeated validated workloads found instruction-loop machine capture, opcode revalidation
and ARC root retirement alongside decoding and memory copying. The candidate removes the
per-instruction machine root while retaining successor validation and immutable observable exits;
it changes no gas, protocol, memory or resource checks.

Preserved baseline/candidate binaries were run twice in opposite orders. Each invocation retains
the established three warmups and ten validated measured samples per guest. Median native times
across the twenty measured samples per variant were:

| Fixed guest | Before (µs) | Cursor (µs) | Less execution time |
| --- | ---: | ---: | ---: |
| Arithmetic, 10000 iterations | 1466.79 | 848.21 | 42.2% |
| Memory aligned, 1000 iterations | 481.08 | 357.83 | 25.6% |
| Memory crossing, 1000 iterations | 632.40 | 554.25 | 12.4% |
| Host/memory aligned, 1000 iterations | 689.12 | 548.94 | 20.3% |
| Host/memory crossing, 1000 iterations | 835.42 | 748.08 | 10.5% |

The full existing comparison also passes with both active engines and explicit compiled deferral.
Its candidate native/PolkaVM ratios remain roughly 7.5–18.2×; some reference/arithmetic samples
are marked noisy by the existing report heuristics. These are bounded local microbenchmarks,
without CPU isolation or deterministic instruction/cache counts; no whole-client throughput,
Linux timing, compiled comparison or full parity claim follows. Input/output validation and all
samples remain intact. Baseline/candidate reports, exact build/source metadata, native binaries,
paired samples and sampling evidence are retained locally under `build/pvm8/perf-baseline` and
`build/pvm8/perf-candidate`; reproduce with `make bench-pvm` on the compared revisions.
Further profiling and focused fuzzing remain required work toward interpreter competitiveness.


## Bounded decoder memo, 2026-10-23

After the cursor change at `66726e17`, profiling still identified operand decoding on the hot loop.
The invocation-local sixteen-slot memo reuses only genuine scalar decodes from the same immutable
program, including host resumptions. A first form copied a full cached result to a temporary;
paired measurement improved arithmetic but regressed memory by about 11%, so that form was rejected.
Direct slot inspection with an inline helper removes that extra copy. No checks or fixtures changed.

Preserved cursor/direct-memo binaries, run in two opposite orders with the same validated three
warmups/ten measured samples per fixed guest, gave these native medians:

| Fixed guest | Cursor (µs) | Direct memo (µs) | Less execution time |
| --- | ---: | ---: | ---: |
| Arithmetic, 10000 iterations | 864.56 | 536.15 | 38.0% |
| Memory aligned, 1000 iterations | 362.90 | 318.54 | 12.2% |
| Memory crossing, 1000 iterations | 533.75 | 501.48 | 6.0% |
| Host/memory aligned, 1000 iterations | 557.10 | 499.27 | 10.4% |
| Host/memory crossing, 1000 iterations | 728.44 | 678.62 | 6.8% |

The full unchanged pinned PolkaVM interpreter comparison passes; its five native/reference ratios
remain approximately 5.5–19.0×, so this is progress toward competitiveness, not parity. Sampling and
raw validated comparisons are retained under `build/pvm8/cache-direct`; the rejected experiment
is retained separately under `build/pvm8/cache-candidate`. The same local timing/no-isolation,
no deterministic instruction-count, no compiled comparison and no full-client throughput limits
apply. Compiler/toolchain/fixture/source identities and every raw sample remain in the reports.


## Scalar page-span resolution, 2026-10-23

A new baseline from merged master `9eb56ba7` uses the current checked ARC/Clang
ThinLTO profile, unchanged five guests and pinned PolkaVM interpreter. Fresh macOS
sampling of repeated validated workloads identified scalar preflight, page copying
and allocation in the memory paths. This change resolves at most two page slots
once per scalar access and reuses them through permission checking and byte transfer.
All fault precedence and immutable snapshot contracts remain intact.

Preserved binaries ran in two opposite orders with three validated warmups and ten
measured samples per guest in each pass. Native medians across twenty samples were:

| Fixed guest | Before (µs) | Page spans (µs) | Less execution time |
| --- | ---: | ---: | ---: |
| Arithmetic, 10000 iterations | 578.98 | 587.94 | No established change |
| Memory aligned, 1000 iterations | 332.00 | 271.69 | 18.2% |
| Memory crossing, 1000 iterations | 511.75 | 440.25 | 14.0% |
| Host/memory aligned, 1000 iterations | 471.88 | 409.13 | 13.3% |
| Host/memory crossing, 1000 iterations | 646.96 | 595.79 | 7.9% |

The full native/pinned interpreted comparison also passes, with a remaining gap of
roughly 6–17× across these guests. That full run includes marked noisy rows and large
outliers; its raw samples remain retained. These paired local measurements have no
CPU isolation or deterministic instruction/cache counts, and arithmetic's small
change is within noise. No Linux timing, compiled comparison or whole-client
throughput claim follows. Baseline/profile and candidate/paired evidence are retained
under `build/pvm9/baseline` and `build/pvm9/spans`. Reproduce the complete comparison
with `make bench-pvm` at the compared revisions. Page-image copying remains a major
profiled cost for subsequent work; fuzzing is deferred by maintainer instruction.


## Scalar register writes, 2026-10-23

Profiling the checked interpreter identified copied register-file results in its
arithmetic path. The arithmetic evaluator now returns a guarded scalar destination
and value for the executor's private CPU cursor; compatibility callers still obtain
a complete copied register array. The arithmetic equations, gas ordering and source
alias contract remain unchanged. An out-of-line form improved arithmetic but
regressed aligned memory/host guests, so it was rejected; inlining the scalar
calculation removed that result-transfer overhead.

The accepted form was measured in two independent opposite-order comparisons of
preserved binaries, with the unchanged five guests and checked ThinLTO profile.
The confirmation's medians across twenty measured samples per variant were:

| Fixed guest | Page spans (µs) | Scalar writes (µs) | Less execution time |
| --- | ---: | ---: | ---: |
| Arithmetic, 10000 iterations | 590.88 | 479.10 | 18.9% |
| Memory aligned, 1000 iterations | 264.65 | 254.19 | 4.0% |
| Memory crossing, 1000 iterations | 426.44 | 407.81 | 4.4% |
| Host/memory aligned, 1000 iterations | 407.35 | 405.04 | No established change |
| Host/memory crossing, 1000 iterations | 581.50 | 575.56 | No established change |

The earlier accepted comparison showed 17.3% arithmetic and 5.1–8.2% memory savings;
host differences remained within a few percent. Complete final registers, memory,
gas and host counts validate every sample. The full pinned interpreter comparison
passes and still shows roughly 4.8–15.2× native/reference ratios on this host. Raw
rejected/accepted/confirmation evidence lives under `build/pvm9/writes`,
`build/pvm9/writes-inline` and `build/pvm9/writes-inline-confirm`. Existing local
noise, no-isolation, no deterministic-counter, no Linux/compiled/full-client claim
limits remain. Arithmetic witnesses, dependent chains, execution and guarded-result
controls are recorded in [the register contract](pvm-registers.md#scalar-write-evaluation-2026-10-23).


## Causing-PC cursor, 2026-10-23

After scalar register writes, the execution loop still copied a complete CPU file
and retained an extra memory owner before each instruction. The evaluator already
guarantees that OutOfGas/Fault/Host leave registers and memory untouched; only Host
needs its causing PC restored. Keeping that PC alone removes unnecessary copies and
ARC traffic while retaining all charged-state and terminal-mutation rules.

Two opposite-order preserved-binary comparisons showed arithmetic medians of
492.00→471.40 µs (4.2% less time) and 498.04→468.92 µs (5.8%). The other four guests
showed no consistent change beyond a few percent. Every sample validates complete
state. The full pinned interpreter comparison passes and still shows roughly
4.9–15.3× ratios. Evidence is retained under `build/pvm9/exits`,
`build/pvm9/exits-confirm` and the preceding fresh `build/pvm9/writes-profile`.
The same checked ThinLTO, fixed inputs, local noise/no-isolation and no Linux,
compiled, deterministic-counter or full-client performance claim limits apply.


## Persistent page chunks, 2026-10-23

Fresh sampling after scalar writes attributed much of memory execution to the two
full-image copies made when cloning a 4096-byte page. Private persistent 512-byte
chunks let scalar stores copy at most two payloads while retaining complete public
page images and immutable predecessor snapshots. Host writes copy only intersected
chunks; permission changes share immutable payloads. Page sizes, budgets, access
checks, fault precedence, guest fixtures and pinned toolchains stay unchanged.

Two independent opposite-order comparisons confirmed the improvement. Confirmation
medians across twenty validated samples per preserved binary were:

| Fixed guest | Prior cursor (µs) | Chunked pages (µs) | Less execution time |
| --- | ---: | ---: | ---: |
| Arithmetic, 10000 iterations | 481.19 | 487.27 | No established gain |
| Memory aligned, 1000 iterations | 267.12 | 149.54 | 44.0% |
| Memory crossing, 1000 iterations | 415.52 | 188.46 | 54.6% |
| Host/memory aligned, 1000 iterations | 394.17 | 294.23 | 25.4% |
| Host/memory crossing, 1000 iterations | 554.33 | 331.54 | 40.2% |

The first comparison gave 42.8–55.0% memory and 25.3–41.9% host/memory savings.
Arithmetic was 1.3–4.1% slower across those comparisons on this shared host; no
arithmetic improvement is claimed. The full pinned interpreted comparison passes,
with native/reference ratios now roughly 4.3–8.9×. Marked noisy rows and all outliers
remain in its reports. Baseline, candidate and confirmation artifacts remain under
`build/pvm9/exits`, `build/pvm9/chunks` and `build/pvm9/chunks-confirm`.

Capturing a complete page now constructs eight chunk owners, and page observations
assemble them into a copied array. Those preparation/validation operations remain
outside the execution timer. The full benchmark retains native one-time preparation
observations (about 2–8 µs in this candidate run); two per guest do not establish a
preparation-speed change or cross-runtime preparation comparison. Steady-state
execution gains do not imply lower setup cost, whole-client throughput, Linux or
compiled performance. Checked ARC/Clang ThinLTO and all normal assertions/bounds
checks remain enabled. Fuzzing remains deferred.


## Private host-response continuation, 2026-10-23

Sampling after chunked pages identified host response application and resumed-machine
capture. Both host APIs now retain a validated private continuation across responses,
while still publishing every actual immutable callback/terminal observation. Public
response application keeps its complete validation and owned-result contract.
Separate by-reference loop forms improved hosts but regressed ordinary guests by
roughly 8–12%; those forms were rejected. One original transition loop with a private
continuation seed at entry preserves the ordinary optimized CPU layout.

The accepted form was measured in two opposite-order preserved-binary comparisons.
Final confirmation medians across twenty validated samples per binary were:

| Fixed guest | Chunked pages (µs) | Host cursor (µs) | Less execution time |
| --- | ---: | ---: | ---: |
| Arithmetic, 10000 iterations | 471.35 | 469.58 | No established change |
| Memory aligned, 1000 iterations | 148.02 | 147.54 | No established change |
| Memory crossing, 1000 iterations | 183.58 | 183.94 | No established change |
| Host/memory aligned, 1000 iterations | 284.10 | 220.12 | 22.5% |
| Host/memory crossing, 1000 iterations | 319.69 | 256.19 | 19.9% |

The preliminary accepted comparison showed 16.6% and 19.9% host savings, with ordinary
guests within a few percent. The full pinned interpreted comparison passes; the
remaining local ratios are about 3.5–8.8×. Evidence lives under
`build/pvm9/chunks-profile`, `build/pvm9/host-cursor-seeded` and
`build/pvm9/host-cursor-final`. Rejected forms are retained separately under the
other host-cursor experiment directories. The same fixed inputs, checked ThinLTO,
all-state validation and local noise/no-isolation limits apply; no Linux, compiled,
deterministic-counter or whole-client throughput claim follows. Fuzzing remains
deferred. Further work should address profiled allocation/copying costs and broader
representative instruction/memory working sets.
