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
producing expectations. The original five fixed guests exercise arithmetic/branches (10000 loop
iterations), scalar memory (1000 aligned/crossing iterations) and memory/host loops
(1000 aligned/crossing iterations). Five additional guests measure arithmetic at 1/16
iterations, a mixed bit-operation loop and aligned/crossing scalar loops over 128
sparsely mapped pages. An alternating two-block guest additionally isolates pipeline
pricing reuse. All use finite gas and local native step limits.

## Build and measurement contract

The native driver uses pinned Nimony 0.6.3 nightly
`4724f66c2e01b17810c844f26575b2317995fda2`, ARC, Clang, LTO and checked release
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
The raw fixture has `PVMBEN01` framing, eleven 273-byte record headers and bounded blobs;
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


## Adaptive scalar working memory, 2026-10-23

Repeated scalar stores previously cloned a page-vector/header/chunk successor on
every instruction. Bounded execution now activates private write epochs after three
successful direct stores, clones each touched chunk once, and freezes only actual
observable exits. Public snapshots and callback-retained roots remain immutable.
A sampled allocation/copying hotspot motivated this change; no checks, input bytes,
expected results or compiler flags were weakened.

Opposite-order preserved-binary comparisons retain twenty validated samples per
variant. Final confirmation against the published host cursor gives:

| Fixed guest | Host cursor (µs) | Working memory (µs) | Less execution time |
| --- | ---: | ---: | ---: |
| Arithmetic, 10000 iterations | 488.96 | 519.92 | 6.3% slower |
| Memory aligned, 1000 iterations | 155.94 | 105.62 | 32.3% |
| Memory crossing, 1000 iterations | 192.52 | 110.92 | 42.4% |
| Host/memory aligned, 1000 iterations | 232.69 | 235.81 | No established change |
| Host/memory crossing, 1000 iterations | 268.81 | 264.08 | No established change |

The preliminary comparison showed 31.3–40.7% memory savings, arithmetic 3.7% slower
and host differences within a few percent. Arithmetic regression is an explicit
tradeoff of this integrated form, not an arithmetic speedup. Further register and
instruction work must address it. The full pinned interpreted comparison validates
all five guests, with provisional ratios roughly 2.6–6.0× on this run. Several rows
are marked noisy; every outlier remains in the report. Evidence is retained under
`build/pvm9/working-memory`, `working-memory-final` and `working-memory-confirm`.
The same local macOS shared-host/no-isolation limits apply. Preparation remains
outside execution timing. No deterministic-counter, Linux, compiled or whole-client
throughput claim follows, and fuzzing remains deferred. M1 framing completion and
remaining full STF/JAM parity are unchanged.


## Broader invocation, integer and page dimensions, 2026-10-23

The benchmark now retains the original five record byte sequences and adds five
related workload dimensions as one grouped feature. The historical five-row corpus
hash is independently reconstructed in tooling tests. Complete expected outcomes
remain authored independently; pinned PolkaVM supplies only a public-API cross-check.

* Arithmetic at 1 and 16 iterations separates short-invocation latency from the
  existing 10000-iteration throughput loop. Setup/reset remains outside execution.
* A 1000-iteration dependent bit loop combines 64-bit population/leading/trailing
  counts, byte reversal, rotation, XOR, arithmetic and a real backward branch.
  Python mathematical/byte operations derive every final register; a fixed final
  witness additionally protects those expectations.
* Sparse aligned/crossing loops map 64 two-page pairs separated by two-page holes,
  retaining 128 page payloads. Both embeddings validate every mapped byte and every
  hole after every sample. Native additionally preserves every original snapshot.
  Guest work touches the original first pair; this measures page-table-size overhead,
  not random traversal across the whole mapped payload or a larger instruction set.

Both embeddings use the same ten owned records and strict 13-observation-per-row
parser. Missing new rows cannot become a successful report. No timeout/price/checked
profile, upstream source, dependency pin or compiler-deferral policy changed. The
native public execute/host entry points retain their normal finite budgets.

Initial expanded observations show approximately 0.6/1.4 µs native execution for
1/16-iteration arithmetic versus about 1.4/1.5 µs in the pinned interpreter. These
short timings are close to timer/scheduling overhead and do not establish whole-client
latency superiority. Mixed bits remain roughly 5.7× slower, and sparse memory roughly
2.9–6.3× slower. They identify optimization targets beyond the five original loops.
Full raw samples, noisy rows, hashes and preparation observations remain under
`build/pvm9/working-sets`; local shared-macOS limits still apply. No claimed Linux,
compiled, deterministic-counter, random-access or full JAM performance follows.
Fuzzing remains deferred. Rejected operand-dispatch experiments produced no reliable
gain and were excluded from this production tree; the arithmetic issue remains open.


## Bounded bit-count arithmetic, 2026-10-23

Sampling the new mixed-bit guest located the inlined trailing-count loop at
`executeBudget` offset 4040 in the preserved profile binary; emitted instructions
confirm the repeated bit test/shift. Repeated successor/opcode lookups and decoder
misses also remain substantial. Replace population/leading/trailing bit traversal
with fixed unsigned word operations for all six 32/64-bit instructions. Explicit
zero handling and low-word masking retain the existing mathematical contract.

Two opposite-order preserved-binary comparisons confirm a mixed-bit improvement:
152.81→128.42 µs (16.0% less time), then 146.81→127.00 µs (13.5%). The latter retains
twenty validated samples per binary. Ordinary arithmetic measured 3.5% slower in the
first comparison and 0.5% faster in confirmation; no consistent ordinary arithmetic
change is established. Memory, host, sparse and short-call differences also vary
within a few percent, so no broad execution improvement is claimed. All ten guests
pass the full pinned interpreter comparison; its mixed-bit ratio is about 5.1×.

Evidence lives under `build/pvm9/working-sets-profile`, `bit-counts`,
`bit-counts-paired` and `bit-counts-confirm`. Profiles/word algorithms and new literal
width/alias witnesses are part of the same feature. Checked ThinLTO and every normal
contract remain enabled; no architecture-specific hook, pin change or fuzzing work
is involved. Shared-host/local macOS limits, compiled deferral and open full JAM
parity still apply. Next work should reduce measured decode/successor lookup costs
without weakening invalid-successor or instruction-budget behavior.


## Retained decoded validation and paired instruction memo, 2026-10-23

Successful decoded instructions now carry a private fallthrough fact established
by the immutable owner's complete validation. Nonterminating execution reuses it
instead of looking up the same sequential opcode again; arbitrary control targets
retain their complete checks. The same fixed sixteen decoder results now have
paired alternatives, retaining colliding hot PCs without increasing capacity.
Natural address-modulo-sixteen hits remain first; a miss checks the paired slot.
Only successful new decodes fill/replace entries, with eight bounded replacement
flags and full-address tags. No program/page/callback owners enter the memo.

The initial address-comparison form produced only small differences. A fixed-first
bucket form improved mixed bits but cost several percent in host/memory guests;
the accepted natural-slot-first form preserves ordinary hits. Two opposite-order
preserved-binary comparisons of the grouped feature confirm mixed-bit savings:
131.04→112.52 µs (14.1%) and 127.50→107.54 µs (15.7%). Ordinary arithmetic was
0.8–3.3% slower, and aligned hosts about 1.5–1.7% slower across these comparisons;
these small observed costs are retained explicitly, with no broad speedup claim.
Other guest differences vary within a few percent. Sub-microsecond short-call
observations remain especially sensitive to timer granularity and scheduling.

The complete pinned ten-guest comparison passes, with the mixed-bit gap now roughly
4.2×. Every raw sample/noise flag remains under `build/pvm9/fallthrough-preferred`,
`fallthrough-preferred-paired` and `fallthrough-preferred-confirm`; earlier measured
forms remain in the other fallthrough directories. Literal two/three-way collisions,
capacity pressure, nested owners, sealed metadata, failed/default access and final
conditional gas/budget ordering join the existing full CPU/page/reference controls.
Checked ARC/Clang ThinLTO, pins and assertions/bounds remain unchanged. Local macOS
limits, compiled deferral, deferred fuzzing and open full STF/JAM parity still apply.


## Multiple block prices and exact cached starts, 2026-10-23

The new 1000-iteration alternating-block guest adds four attempted instructions per
iteration and a dynamic halt. Its independently priced blocks at PCs0/8 cost15/22;
terminal PC21 costs22. Initial gas includes every visit plus7 untouched gas. Both
native and pinned public PolkaVM APIs validate these prices and full outcomes.
A code-prefix-aware test-only simulator keeps raw target bytes at their actual PCs;
all previous default-prefix gas fixtures and the original ten benchmark records
retain their exact historical hashes. Compiled comparison stays deferred.

Before optimization, the new guest took466.85 µs against about15.1 µs interpreted,
a gap of30.9×. Sampling found pipeline pricing dominant. A private four-price memo
now retains the first block plus three recent successes; exact cached starts reuse
known membership before rescanning. Every visit still checks/debits gas. Failed
simulations, new programs/limits, callbacks and local failures preserve the existing
contracts, with no new caller resource default or public mutable state.

Two opposite-order preserved-binary comparisons confirm the effect. Final confirmation
medians across twenty validated samples per matched eleven-guest binary were:

| Fixed guest | Prior single price (µs) | Four prices (µs) | Less execution time |
| --- | ---: | ---: | ---: |
| Arithmetic, 10000 iterations | 507.21 | 448.15 | 11.6% |
| Memory aligned, 1000 iterations | 103.33 | 98.29 | 4.9% |
| Memory crossing, 1000 iterations | 111.81 | 106.08 | 5.1% |
| Mixed bits, 1000 iterations | 114.00 | 110.50 | 3.1% |
| Alternating blocks, 1000 iterations | 485.54 | 61.48 | 87.3% |

The first comparison showed9.8% arithmetic and87.6% alternating-block savings.
Host differences were1–5%, sparse differences about1–4%; these small changes and
sub-microsecond short-call observations are not broad whole-client claims. The full
pinned comparison passes all eleven guests; the alternating-block gap is now about
3.9×. Evidence remains under `build/pvm9/multiblock-baseline`, `multiblock-candidate`,
`multiblock-paired`, `multiblock-confirm` and the separate sampling wrappers.

All warmups/outliers/noise flags and exact source/fixture/binary identities remain
recorded. Normal checked ARC/Clang ThinLTO, pins and timing/validation boundaries are
unchanged. Post-change sampling now ranks basic-block membership/control checks well
ahead of pipeline pricing; these are the next measured target. Sampling ranks are
directional, not deterministic counters. No Linux, compiled or full JAM throughput
result is claimed. Fuzzing remains deferred, and full STF/JAM parity remains open.


## Retained static control targets and real-sieve cross-check, 2026-10-23

Post-pricing sampling identified repeated block-membership checks on the small
alternating guest. The decoder now seals static target membership in its genuine
result, and the control handler reuses the result without separating operands from
validation facts. Both conditional successors remain required; dynamic checks, gas
ordering, bounds/assertions and the final control opcode check remain enabled.

Two opposite-order preserved-binary comparisons against the published four-price
parent show the following execution-time reductions on this Apple M1 Max:

| Fixed guest | Less execution time across both comparisons |
| --- | ---: |
| Arithmetic,10000 iterations | 35.9–36.5% |
| Mixed bits,1000 iterations | 32.1–33.2% |
| Alternating blocks,1000 iterations | 33.2–33.7% |
| Aligned memory,1000 iterations | 20.6–20.8% |
| Host loops | approximately6–11% |
| Sparse memory | approximately13–17% |

Crossing-memory confirmation was noisy for both binaries, so no consistent gain is
established for that row. Every sample remains recorded. Short-call observations
remain timer-sensitive. Accepted source/binary identities and all eleven validated
pinned comparisons are preserved under `build/pvm9/static-target-sealed`,
`static-target-sealed-paired`, `static-target-sealed-confirm` and `static-target-final`.
Separate rejected handler-argument/check-removal experiments remain in ignored
artifacts; their regressions are excluded from production, whose hashes match the
accepted, tested sealed-result implementation.

A real upstream Rust sieve supplies a necessary larger-working-set cross-check.
The independently prepared experiment in [PR1309](https://github.com/jacogr/ragnarok/pull/1309)
provides one linked guest and an explicitly interpreted PolkaVM host. This branch
uses ordinary public production execution, with no prepared execution extension.
The linked guest includes an extra checked prime-count export, so these results
must not be compared directly with stock published sieve numbers. At limit100000,
104 invocations across two reversed orders validate prime count9592, all13 registers,
all262 mapped pages/permissions, gas, terminal state and unchanged source snapshots.
Three warmups per engine/pass leave twenty measured process-CPU samples per engine:

| Engine, same linked guest/input | Median process CPU (ms) |
| --- | ---: |
| Frozen master `b723f0c1aeaa3b807f062af69004f1fd76352ea5` | 236.186 |
| Published four-price parent | 119.270 |
| This static-target implementation | 118.750 |
| Pinned PolkaVM interpreter | 5.937 |

This change establishes no real-sieve gain over its parent. The batch approximately
halves frozen-master time here, while remaining about20× slower than interpreted
PolkaVM. Frozen master source hashes are checked against Git; linked input, binary,
source/toolchain identities and every sample are retained in `build/pvm9/sieve-probe`.
A separate41-run validated sampling pass still finds block pricing dominant on this
larger guest, making pricing working-set behavior a future investigation. Sampling
is directional and excluded from timing. No10-million-input result is claimed for
this branch. Pins and normal checked ARC/Clang ThinLTO remain unchanged.

These are local macOS observations without CPU isolation or deterministic counters;
no Linux, compiled-backend or whole JAM throughput result follows. Fuzzing remains
deferred. Documented M1 framing completion remains scoped; full STF/JAM parity is
open. Work pauses after this review unit until the maintainer resumes after merging.


## Secondary block-price working set, 2026-10-23

A fresh baseline on master `cdc9dc7a` uses the October23 Nimony pin `4724f66c2`.
Historical tables above retain their original compiler identity; current comparisons
use matched checked release ARC/Clang ThinLTO binaries, unchanged Rust/PolkaVM pins
and the exact same linked sieve/input and eleven synthetic fixtures.

The chosen tiered cache preserves the original first-plus-three hot lookup and
consults a sixteen-entry two-way secondary table only on misses. Only successful
prices enter either level, exact tags protect collisions, and every visit still
checks/debits gas. A separate original-source diagnostic trace and policy replay
identify working-set pressure; their instrumented durations never enter these tables.
The final insertion policy alternates ways without mutating lookup hits, rather
than claiming the offline LRU experiment's exact miss count.

Two reversed-order comparisons (an isolated candidate and its final production
integration) validate thirteen invocations per engine/pass, discarding only the
three declared warmups from timing summaries. Full terminal registers, all mapped
bytes/permissions, exact gas, prime count9592 and unchanged source snapshots are
checked on every native invocation. Assertion-failure controls pass before timing.
Each comparison retains twenty measured process-CPU samples per engine:

| Sieve limit100000 | Baseline CPU (ms) | Candidate CPU (ms) | PolkaVM interpreted CPU (ms) |
| --- | ---: | ---: | ---: |
| First matched comparison | 122.054 | 27.328 | 6.223 |
| Production confirmation | 119.472 | 26.831 | 5.965 |

This is approximately77.5% less execution CPU time, or4.5× faster than the matched
baseline. The remaining sieve gap is about4.4–4.5× to interpreted PolkaVM. This
fixture has an extra checked prime-count export; it is not directly comparable to
stock published sieve scores. No10-million-input result follows.

The larger cache has explicit small-workload costs. Matched synthetic comparisons
show arithmetic4.2–5.9% slower and mixed bits8.4–13.6% slower. Memory/sparse changes
range from near-flat to about7.5% slower; hosts vary in both directions within about4%.
Alternating blocks range from flat to2.1% slower. Sub-microsecond calls remain too
sensitive to timing granularity for a broad claim. A direct replacement cache and
an outlined lookup without the hot ring were measured and rejected for larger
small-workload regressions. No samples are removed to conceal these tradeoffs.

Raw reports, source/fixture/binary identities and rejected experiments remain under
`build/pvm10/baseline`, `price-working-set-final`, `price-working-set-tier-paired`,
`price-working-set-final-paired` and `sieve-probe`. Existing synthetic fixtures remain
byte-identical. The scope remains local Apple M1 Max/macOS without affinity/frequency
isolation or deterministic hardware counters. No Linux, compiled or whole JAM
throughput claim follows; full STF/JAM parity remains open and fuzzing is deferred.


## Decoder working set after secondary pricing, 2026-10-23

The post-pricing sieve profile ranks execution and instruction decoding ahead of
pricing. A separate fully validated diagnostic copy records1166742 decoder lookups
to13417 distinct PCs at limit100000. Offline replay of the exact replacement policy
finds561880 misses at16 results,96933 at32 and78964 at64. Multiplicative indexing
at16/32 gives312318/100606 misses, so natural paired32 remains the selected small
bounded policy. These are untimed trace diagnostics; no deterministic hardware
counter claim follows. An isolated64-result variant did not establish a compelling
additional timing benefit to justify twice the selected storage.

Both the isolated32-result candidate and its production integration are measured
against preserved PR1345 parent binaries with the same checked ARC/Clang ThinLTO,
October23 Nimony pin, exact linked sieve/input and explicit PolkaVM interpreter:

| Sieve limit100000 | Parent CPU (ms) |32-result CPU (ms) | PolkaVM interpreted CPU (ms) |
| --- | ---: | ---: | ---: |
| First matched comparison |27.453 |22.636 |6.200 |
| Production confirmation |26.675 |22.091 |6.018 |

Execution CPU falls17.2–17.5%, leaving about3.7× to interpreted PolkaVM. Every
warmup/measured invocation retains full register/gas/mapped-memory/permission checks,
known prime count9592, source-snapshot preservation and assertion controls. Two
reversed orders retain twenty measured samples per engine, without discarded
outliers. Preparation/validation and the separate trace are excluded from timing.

Synthetic paired comparisons show arithmetic2.6–3.1% slower. Mixed bits varies
from5.1% slower to flat; other substantial rows vary by about3%, with no broad
small-workload gain established. Very short calls remain sensitive to sub-microsecond
timer resolution. All eleven fixtures pass unchanged; raw values, source/binary
identities and32/64 experiments remain under `build/pvm10/decoder-probe`,
`decoder-slots32-paired`, `decoder-slots64-paired`, `decoder-final` and
`decoder-final-paired`. Local macOS/no-isolation limits, compiled/fuzzing deferral
and open full STF/JAM parity remain unchanged.
