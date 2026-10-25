# Lazy prepared-block execution

## Authorized scope and completion

Build an optional interpreted execution tier for large programs, alongside the existing
interpreter. Base: master `895f300e3efc5ea8fcdb88cccb5267e313818316`. Gray Paper pin
1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d and existing scoped PVM interpretations
remain authoritative. No dependency, sandbox, fault-order or runtime-check changes.
The ongoing decoded-memory/DOOM investigation in another checkout stays independent.

A prepared owner retains one immutable Program and a fixed pricing policy. Lazy
visited-block segments retain original PCs, genuine decoded operands, selected
operation handlers and successful whole-basic-block prices. CPU, memory, paid gas,
step/callback budgets and outcomes remain invocation-local. Copies share cache identity;
exclusive synchronous use is required and recursive use of that same owner is refused.
An independent owner can execute inside a callback.

Only visited segments are expanded. Fixed-size segments permit arbitrarily long
admitted basic blocks without whole-program instruction expansion. Segment boundaries
never create guest block boundaries or additional gas charges. Interior entry, paid
fault retry, host continuation, invalid targets and terminal PC normalization retain
existing behavior. Host replies invalidate all invocation memory staging; they cannot
change the program. Cached facts never authorize current memory or certify paid gas.

Retained payload has explicit byte and slot limits, including the fixed index and
operation arrays. Replacement evicts facts; it never changes guest state. Preparation
scratch is bounded by one segment and must be accounted separately from retained data.
Statistics distinguish preparation, hits, evictions and retained capacity. Preparation
limits are local failures, distinct from guest out-of-gas and faults. No fallback
silently substitutes the original interpreter after a local failure.

Completion requires checked differential tests for every opcode, every guest outcome,
gas boundaries, host callbacks/reentrancy/refusals, fault repair, source snapshots,
cache eviction and working sets larger than the cache. Frozen upstream-generated cases
must use the new path too. Preparation, first execution and reused execution must be
reported separately, including retained bytes and miss counts. Representative guests
include Pinky, sieve and memory/indirect workloads; larger-program admission can reuse
the independently qualified DOOM harness when available. Claims about speed require
paired checked measurements; correct execution alone establishes no speedup.

## Implemented interface and bounds

`newPreparedProgram(program, limits)` returns a guarded `PreparationResult[PreparedProgram]`.
`PreparedLimits` supplies nominal `PreparedByteLimit`, `PreparedBlockLimit` and `GasCycleLimit`
values. `execute(machine, stepLimit, prepared)` and both typed-refusal and response-only
`executeWithHost` overloads use the new representation. `programOf` retains the immutable
source; `preparedInfo` returns copied observations. Default owners and mismatched source
identities are refused. The existing interpreter remains the default.

The slot limit is 1..65,536. Each exact-PC-tagged hash slot retains at most one segment,
with up to 256 instructions. Hash collisions replace that slot; byte pressure evicts slots
in round-robin order. Very small admitted byte budgets reduce segment length. Cache misses
reconstruct facts with the same checked decoder and semantic helpers. No executable native
code is generated. Memory access permissions and current dynamic targets remain checked at
execution; preparation never authorizes a memory operation.

Retained accounting includes the slot pointer array, segment bodies and operation arrays.
It excludes allocator headers and the original immutable program owner, which is shared.
A fixed 256-record preparation scratch array and one new segment can temporarily coexist
with the retained cache; `peakBytes` conservatively accounts for these separately from the
retained byte ceiling. `residentBlocks` and `preparedBlocks` count bounded segments, which
can split a long guest basic block. Operation totals, hits, evictions and peak bytes are
copied diagnostics; cumulative counters saturate. Exact prices are learned only on uncharged
entry, under the captured cycle policy. An already paid entry does not request pricing.

The owner requires exclusive worker use. Copies share its identity, and synchronous recursive
execution of the same owner returns `PreparedProgramBusy`. This guard is not a thread lock.
A host callback may execute through an independent owner. No machine, host closure or mutable
memory workspace is retained in the reusable owner.

## Verification and measurements

Checked local verification on macOS arm64 with the pinned Nimony nightly covers all 139
opcodes, paid/unpaid entry, gas and attempt boundaries, memory permission/address cases,
interior entry, a 701-instruction block split across a two-slot cache, independent tiny-byte
cache pressure, repeated execution,
host outcomes/refusals/reentry, fault repair and unchanged source snapshots. A 1,000-owner
ARC lifetime probe returns occupied memory to its initial value. Private owner/result fields
have compile-failure guards. The 32 mixed reference programs exercise all execution modes
in 1,280 scenarios; frozen upstream reference frames also execute through this tier.

`make check-pvm-prepared` builds one checked ARC/Clang ThinLTO candidate and verifies the
full maintained guest matrix against pinned PolkaVM interpreter states, in both process
orders. Local clocks are disabled. Every guest checks registers, gas, permission/page bytes
and unchanged source state. The first complete prepared execution retains these payloads:

| Guest | Size | Retained bytes |
| --- | ---: | ---: |
| sieve | 1,000 | 291,056 |
| sieve | 100,000 | 1,334,600 |
| minimal | 1,000 | 136,496 |
| minimal | 100,000 | 136,624 |
| memset | 1,000 | 164,400 |
| memset | 100,000 | 165,712 |
| Pinky | 1 | 682,920 |

A separate 13-execution fresh-state reuse check passed for the four larger guest cases.
Hash collisions still cause re-preparation: reused execution is not necessarily fully warm.
These are correctness and storage observations, not speedup evidence.

`make profile-pvm-prepared` is the explicit Linux x86_64 measurement entry point. The manual
CI `prepared-pvm` selection installs pinned Valgrind 3.22.0, verifies selected-scope controls,
collects cold execution instruction counts, then runs paired timings against PolkaVM
interpreted. Each process supplies 13 fresh-state executions: three warmups and ten measured
samples, with both process orders retained. Constructor, first execution, reused samples,
cache evolution and raw profiles are stored under `build/tests/pvm-prepared-blocks/`.
Clock reads are outside the instruction-count phase. Assertion controls remain enabled.

The existing dynamic, complete-plan and prepared paths share the candidate binary. This
compares execution models but does not establish binary identity with a separately built
master. Constructor cost and cold execution must be considered alongside reused execution;
retained payload and cache misses must accompany any speed claim. Larger-program admission
beyond these maintained guests remains a separate qualification step.

## Handler-call investigation

The dd75ce74 Linux Pinky profile records 28,448,007 simulated indirect misses at the
single selected-handler call (32,055,270 calls), over 99.8% of all indirect misses.
The two most frequent targets are `add_imm_64` (149; 3,152,504 calls) and
`shlo_l_imm_64` (151; 2,424,254 calls). The first bounded hypothesis was to call those
two existing specialized handlers directly and retain the checked indirect fallback.
No cache layout, arithmetic, gas, memory or host semantics change. Acceptance requires
complete native parity, matched baseline/candidate instruction profiles and paired guest
timings on one runner. Simulated misses are not hardware predictor measurements.

The measurement tool accepts `PVM_PREPARED_BASELINE=<local-ref>` (or `--baseline`)
to run both prepared implementations on the same host. It resolves the ref once,
uses the same current driver, compiles through identical source/cache/output paths,
and requires a repeated candidate build to reproduce the executable bytes. Each endpoint
and the repeated control start with a fresh private compiler cache at that same path. Every
baseline/candidate execution retains the same full-state checks. Baseline and candidate
generated C are archived separately; cold selected-scope profiles precede both-order
timings. The manual CI job captures full history and currently compares against dd75ce74.

The two-handler trial passes checked native opcode/cache/host parity, 1,280 mixed
reference scenarios, all seven guest cases in both orders, and the candidate image
rebuild control. Native source assertions were reshaped to avoid malformed expressions
from an earlier formatter invocation; the corrected final formatted suite passes.
Linux counter/timing qualification completed at a71f0d20; the measured trial was rejected and its runtime changes reverted, as recorded below.

Dispatch attribution additionally collects an isolated fourth execution after three
warmups, using the existing calibrated function-return dump controls. Every preceding
return part must be complete, the final process dump must be empty, and the selected
last part must contain exactly one execution entry. Cold preparation counters and
reused execution counters are labeled separately. This prevents attributing warmed
CPU behavior to a cold preparation delta. Source archives explicitly select the paired
compiler cache rather than relying on unrelated caches from earlier local runs.

The original Pinky cold profile also shows conditional misses dropping from 50,506,033
(planned) to 24,299,409 (prepared). Including indirect misses, combined simulated misses
drop from 67,065,579 to 52,795,793 (21.3%). The increased indirect category alone does
not explain the observed CPU regression. Counter reports therefore include both classes
and combined totals, and reject missing cold/reused profile phases. Hardware predictor,
call/return, register-pressure and front-end costs remain hypotheses, not established causes.

## Rejected direct-call trial

[Linux run40193794357](https://github.com/jacogr/ragnarok/actions/runs/40193794357)
qualified a71f0d20077c4cbf4d426d6429334286202e1aa2 against prepared baseline
`dd75ce743c406a427a4dfc7d600195faf2ac5473`. All70 engine/order/case runs,24 cold/reused
profiles, native opcode/host checks, reference-state checks, calibrated return dumps,
independent image controls and retained generated-source/profile hashes passed.

The direct149/151 paths were slower in both process orders. Values below are median CPU
milliseconds from ten reused samples after three warmups; each pair is forward/reversed
process order on the same Linux x86_64 runner.

| Guest | Size | Prepared baseline ms | Direct-call trial ms | CPU change |
| --- | ---: | ---: | ---: | ---: |
| sieve | 100,000 | 11.343 / 10.782 | 14.028 / 14.273 | +23.67% / +32.37% |
| minimal | 100,000 | 25.236 / 25.439 | 32.347 / 32.264 | +28.18% / +26.83% |
| memory fill | 100,000 | 11.034 / 10.921 | 11.502 / 11.538 | +4.24% / +5.65% |
| Pinky | 1 | 397.303 / 390.540 | 441.032 / 423.749 | +11.01% / +8.50% |

The isolated fourth-call Pinky profile reduced indirect misses from28.479M to23.276M,
but conditional misses rose from24.067M to27.979M. Combined simulated misses fell2.46%
and native instructions rose1.09%. Memory fill also reduced native instructions2.37%
and combined misses12.49%, yet ran slower. These observations reject the two direct
fast paths; they do not establish the cause of the original prepared execution regression.
No simulated miss reduction is presented as a speed improvement.

The prepared runtime is restored byte-for-byte to the dd75ce74 source. The strengthened
paired measurement tools, explicit cold/reused profiles, exact generated-source archives,
native test formatting fixes and CI parity check remain.

A separate diagnostic probe confirms that the generated32-byte `InstructionEvaluation`
uses a hidden result pointer on x86_64, in addition to five explicit handler arguments.
The pinned PolkaVM default interpreter also uses a shared indirect call, with an
instance/offset ABI returning a32-bit offset; its optional musttail feature is not enabled
by this benchmark crate. A smaller private handler ABI, register pressure and front-end
behavior are future hypotheses. No ABI refactor or DOOM qualification is included here.

## Reconciliation with merged PVM work

The ordinary prepared-execution PR was reconciled with master
`51ecc125133b838ff7efbe973b8e13831b6cd989`, including decoded memory operand facts
and the headless DOOM attribution/comparison tooling. Runtime changes merged cleanly;
the CI choice list and matching safeguard test retain `prepared-pvm`, `profile-doom`
and `compare-doom`. No ABI experiment is included in this reconciliation.

Combined-tree verification passes the prepared opcode/cache/host suite with balanced
ARC lifetimes, the mixed reference suite, memory-step and scalar-writer suites, all
seven maintained guest cases in both orders, the affected CI/profiler/comparison tests,
formatting and all 441 production-module smoke compilations. Retained prepared payload
sizes are unchanged. Earlier timing tables remain historical evidence from their
recorded revisions; performance against the newly combined baseline must be remeasured.

## Compact handler ABI trial

After rejection of the direct149/151 paths, the next bounded hypothesis changes only
the private handler boundary. A plain invocation-local frame owns CPU, working memory,
dynamic-target cache and immutable program handle. Handlers receive that frame plus
a borrowed prepared operation and return a compact guarded status/exit result. Fault
and host payloads are written to the frame only for those exits. The prepared owner
retains no frame or mutable execution state. Instruction semantics, cache layout,
pricing, scheduling and host-response rules remain fixed.

Acceptance requires complete opcode, gas, memory, fault/host/reentry and ARC parity;
all maintained guests against the frozen prepared baseline on identical build paths;
proof that the generated result fits a register return; and same-runner cold/reused
counts and paired timings. This trial introduces no new public API or unchecked access.

The compact-ABI trial is isolated from the merge-ready prepared PR on
`codex/pvm-prepared-handler-abi`. Its baseline is the reconciled prepared tree
`10af30aabbc901775f556a563b983583a2eb481f`, including the merged memory facts and
DOOM tools. Checked local opcode/host/ARC, mixed-reference and complete guest comparisons
pass on that combined tree. The measurement report additionally records the runner CPU
model. The qualified paired Linux result follows below.

## Qualified compact ABI result (2026-10-25)

Retain the compact ABI: all seven guest/size cases improve in both process orders.
The four main workloads reduce reused CPU time by 23.38–31.35% against the reconciled
prepared baseline. Smaller 1000-size cases also improve by 20.96–31.16%. This is
same-runner evidence for this private boundary change, not a claim of PolkaVM parity.

[Linux run 40198779085](https://github.com/jacogr/ragnarok/actions/runs/40198779085)
passed at candidate `74948c55105ee524370f30dde5e61abbdf9026b3` against
baseline `10af30aabbc901775f556a563b983583a2eb481f` on AMD EPYC 7763,
Linux x86-64, pinned Nimony nightly 4724f66, checked ARC/Clang ThinLTO. The source
change is confined to the prepared handler boundary; existing dynamic/planned paths
share the candidate image, so unrelated layout effects are not separately isolated.

All 70 process runs (13 fresh-state calls each), 24 profiles and four collection
controls passed. The native 139-opcode/host suite passed first. Every timed call
checked terminal PC, all 13 registers, gas, every mapped page byte and permissions,
and the original source state. Both native assertion probes failed with their expected
diagnostic. Candidate and baseline used fresh private compiler caches and identical
build paths; an independent candidate rebuild was byte-identical. Tracked source
hashes match the exact revisions. Downloaded generated-source and retained profile
hashes were independently checked; each selected profile contains exactly one execution.

CPU times below are milliseconds. Reused values are medians of ten calls following
three warmups, with a fresh guest state and a shared prepared cache. Order 1 is dynamic,
planned, prepared, baseline, PolkaVM; order 2 reverses that process order. The planned
constructor and the bounded empty prepared-owner constructor are outside execution timing.

| Guest / size | Order | Dynamic | Planned | Baseline prepared | Compact prepared | PolkaVM interpreted | ABI CPU change |
|---|---:|---:|---:|---:|---:|---:|---:|
| pinky / 1 | 1 | 461.385 | 415.682 | 509.308 | 382.739 | 184.110 | -24.85% |
| pinky / 1 | 2 | 459.805 | 414.827 | 505.545 | 387.359 | 184.521 | -23.38% |
| sieve / 100000 | 1 | 17.528 | 11.007 | 11.882 | 8.247 | 5.563 | -30.59% |
| sieve / 100000 | 2 | 17.438 | 11.049 | 11.941 | 8.198 | 5.534 | -31.35% |
| minimal / 100000 | 1 | 26.910 | 26.337 | 29.226 | 21.726 | 7.489 | -25.66% |
| minimal / 100000 | 2 | 26.942 | 26.288 | 30.137 | 21.719 | 7.458 | -27.93% |
| memset / 100000 | 1 | 12.616 | 12.777 | 12.652 | 9.390 | 4.184 | -25.78% |
| memset / 100000 | 2 | 12.608 | 12.866 | 12.499 | 9.354 | 4.179 | -25.16% |

Cold means sample 0, one observation per process, including lazy preparation; these
single observations are not medians or isolated preparation-cost estimates. Pinky
shows that ordinary runner variation can make a cold call faster than reused calls.

| Guest / size | Order | Cold dynamic | Cold planned | Cold baseline | Cold compact | Cold PolkaVM |
|---|---:|---:|---:|---:|---:|---:|
| pinky / 1 | 1 | 463.585 | 417.549 | 513.529 | 368.606 | 189.022 |
| pinky / 1 | 2 | 448.920 | 407.753 | 511.771 | 389.874 | 189.528 |
| sieve / 100000 | 1 | 17.824 | 11.752 | 20.975 | 16.772 | 6.156 |
| sieve / 100000 | 2 | 17.725 | 12.109 | 20.465 | 16.753 | 6.175 |
| minimal / 100000 | 1 | 28.061 | 27.234 | 29.408 | 22.019 | 7.584 |
| minimal / 100000 | 2 | 27.883 | 27.522 | 30.347 | 22.062 | 7.650 |
| memset / 100000 | 1 | 12.660 | 12.851 | 12.931 | 9.811 | 4.288 |
| memset / 100000 | 2 | 12.804 | 12.847 | 12.905 | 9.734 | 4.299 |

Constructor CPU in microseconds, order 1/order 2. The prepared owner reserves 131,072
bytes and zero decoded operations; lazy work is in cold execution. No complete
PolkaVM module/instance constructor measurement is collected by this harness.

| Guest | Baseline prepared | Compact prepared | Existing complete gas plan |
|---|---:|---:|---:|
| pinky | 4.218/6.502 | 4.549/4.208 | 3033.022/3068.038 |
| sieve | 9.518/4.459 | 4.358/4.097 | 14676.280/14607.952 |
| minimal | 58.750/58.199 | 56.846/57.037 | 34.535/39.434 |
| memset | 5.510/5.631 | 5.860/5.851 | 248.685/250.888 |

Selected reused execution counters below compare baseline → compact. The fourth-call
profile excludes three warmups. Ir counts executed native instructions, not guest
opcodes. Bcm/Bim are simulated conditional/indirect branch misses; these are not
hardware counter readings. Data/instruction cache simulation is disabled.

| Guest | Native instructions | Conditional misses | Indirect misses | Combined miss change |
|---|---:|---:|---:|---:|
| pinky | 4196.494M → 3662.509M | 29.588M → 24.579M | 28.479M → 28.450M | -8.68% |
| sieve | 112.846M → 96.193M | 0.263M → 0.207M | 1.131M → 1.131M | -4.04% |
| minimal | 362.811M → 323.310M | 2.600M → 2.800M | 1.900M → 1.900M | +4.44% |
| memset | 151.676M → 133.370M | 0.501M → 0.301M | 1.100M → 1.100M | -12.49% |

Cold Ir reductions are 9.09% sieve, 10.88% minimal, 11.97% memory fill and 12.66%
Pinky; reused reductions are 14.76%, 10.89%, 12.07% and 12.72%, respectively.
Indirect misses barely change. Minimal gets faster despite 4.44% more combined
simulated misses. The evidence supports reduced call/result and instruction overhead;
it does not establish the hardware-level cause of the measured CPU improvement.

Prepared-cache observations are identical between baseline and compact in both orders.
Minimal retains 9 blocks/59 operations (136,624 bytes), and memory fill retains 63/365
(165,712 bytes), with no evictions. Sieve retains 991/13,226 (1,334,600 bytes) and
continues 48 evictions per repeated call; Pinky retains 792/5,911 (682,920 bytes)
and continues 58 evictions per call. After 13 calls, cumulative evictions are 615 and 751,
respectively; peaks are 1,361,216 and 709,360 bytes. Those continuing rebuilds are a
future cache-policy question, outside this isolated ABI experiment.

The compact tier still takes 1.48× PolkaVM interpreted CPU for sieve, 2.90–2.91×
minimal, 2.24× memory fill and 2.08–2.10× Pinky. Construction, cold execution and
cache churn must remain visible when evaluating larger programs. No further runtime
optimization or default-engine switch is included in this measured increment.

## Compact operand records: next isolated trial

The next stack layer starts from accepted compact-ABI parent
`62201bce1b89cc8e8361c27e40ed34e0bbfd2e0b`. It changes only the private prepared
operand representation and the shared semantic input adapters. No specification,
fixture, compiler, memory-check, scheduling or cache-policy pin changes are included.

The accepted ABI run's fourth-call profiles motivate this scope. The execution owner
and inlined loop/cache work account for 31.72% of Pinky's native instructions, 53.61%
sieve, 21.90% minimal and 41.10% memory fill. Checked scalar load/store functions account
for 36.44%, 17.66%, 50.64% and 31.31%, respectively. These are self instruction shares,
not sampled CPU-time shares. Repricing is comparatively small: inclusive blockGas work
is 0.036% of reused Pinky instructions and 1.041% of reused sieve. Direct-mapped hash
collisions explain the continuing evictions despite unused slots and ample byte budget;
changing replacement policy is a separate experiment.

Each prepared operation now retains a selected handler, causing/successor/static-target
PCs, immediate X/Y bit patterns, copied bounded register coordinates and immutable
fallthrough/target/block-end facts. Only a genuine successful owner decode constructs
these private records. The reusable owner retains no machine, memory or callback state.
Handlers consume these records without repeatedly opening a tagged decoder result or
recomputing the physical successor. Generated-C layout probes confirm 88 → 56 bytes per
record on x86-64, a 36.36% reduction; the compact handler call/return ABI is unchanged.
Sparse-index policy and 256-operation segment ceiling remain fixed; smaller records can
fit more operations under a deliberately tiny byte budget, preserving the same bound.

Arithmetic still uses one shared opcode table, verified identical after whitespace
normalization. The ordinary public evaluator still requires a successful decoder result;
the internal operand adapter does not grant program identity or execution authority.
Conditional comparisons and dynamic address resolution also share their semantic
helpers. Dynamic load-and-jump reads the original base before writing an aliased
register, preserving wrapped 32-bit addition, sentinel precedence and unconditional
load mutations on panic/halt.

The complete prepared opcode/host/cache/ARC suite passes, including 48 independent new
aliased dynamic-jump cases across ordinary/saturated coordinates, signed offsets,
wrapping, empty jump tables and halt sentinel selection. Mixed reference, register and
register-chain suites pass. All seven maintained guest/size cases pass in both process
orders against the accepted ABI parent, with fresh compiler-cache and repeated-image
controls. Formatting and 63 affected Python CI/report checks pass. Exact Linux paired
counts/timings are required before accepting a speed gain; no runtime benefit is yet
claimed for this smaller representation.

The ordinary conditional-control reference, execution-cache and stepping suites also
pass after the shared input adapters were extracted; production semantic smoke checks
pass all 441 modules and the peer entry point. The local timing invocation correctly
refuses macOS: the existing harness reserves counts and clocks for Linux x86-64. Its
passing zero-clock guest comparison remains the local behavior evidence; runtime
qualification proceeds through the existing manual Linux comparison job.

## Qualified compact operand result (2026-10-25)

Retain the compact operand records. The paired prepared comparison improves all seven
guest/size cases in both process orders. The four main workloads reduce reused CPU
time by 6.87–17.11% against the accepted compact-ABI parent. Their ten measured sample
ranges do not overlap the matching parent ranges. Smaller 1000-size cases improve by
8.47–15.21%; no prepared workload regresses in this run.

[Linux run 40205771161](https://github.com/jacogr/ragnarok/actions/runs/40205771161)
passed at candidate `7bd1f77cdd63ca2d6a9561f7403780a26e567db1` against accepted ABI
baseline `62201bce1b89cc8e8361c27e40ed34e0bbfd2e0b`. Machine: AMD EPYC 7763,
Linux x86-64, pinned Nimony nightly 4724f66, checked ARC/Clang ThinLTO.

Qualification passed all 70 process runs (13 fresh-state calls each), 24 profiles and
four collection controls, preceded by the native complete opcode/host suite. Every
execution validated terminal CPU state, all registers, exact gas, mapped page bytes
and permissions, plus source snapshot immutability. Both native assertion probes
produced their expected failures. Fresh compiler caches, identical build paths and
byte-identical independent candidate rebuild controls passed. Tracked source hashes
match the exact revisions. Downloaded generated sources and selected profiles match
their recorded hashes; every selected profile contains exactly one execution. All 70
retained process outputs independently reproduce the report samples/cache metadata.

Reused CPU milliseconds below are medians of ten calls after three warmups. Order 1
is dynamic, planned, compact prepared, ABI baseline, PolkaVM; order 2 reverses it.
Each call starts from the same immutable guest state; prepared facts survive calls.

| Guest / size | Order | Dynamic | Planned | ABI baseline | Compact operands | PolkaVM interpreted | CPU change vs ABI |
|---|---:|---:|---:|---:|---:|---:|---:|
| pinky / 1 | 1 | 474.867 | 427.123 | 392.420 | 365.476 | 189.323 | -6.87% |
| pinky / 1 | 2 | 481.630 | 419.925 | 382.624 | 353.281 | 185.076 | -7.67% |
| sieve / 100000 | 1 | 17.667 | 11.198 | 8.407 | 7.476 | 5.584 | -11.08% |
| sieve / 100000 | 2 | 17.750 | 11.104 | 8.348 | 7.395 | 5.551 | -11.42% |
| minimal / 100000 | 1 | 26.940 | 27.269 | 21.707 | 17.993 | 7.566 | -17.11% |
| minimal / 100000 | 2 | 26.847 | 27.040 | 21.770 | 18.056 | 7.503 | -17.06% |
| memset / 100000 | 1 | 13.483 | 14.416 | 9.388 | 8.525 | 4.193 | -9.19% |
| memset / 100000 | 2 | 13.326 | 14.287 | 9.408 | 8.385 | 4.186 | -10.88% |

Cold sample 0 includes lazy preparation and is a single observation per process, not
a repeated cold median. Constructors are outside these execution clocks. Fresh-state
restoration and final reference comparisons are also outside execution timing.

| Guest / size | Order | Cold dynamic | Cold planned | Cold ABI | Cold operands | Cold PolkaVM |
|---|---:|---:|---:|---:|---:|---:|
| pinky / 1 | 1 | 454.149 | 419.300 | 387.274 | 358.952 | 203.033 |
| pinky / 1 | 2 | 465.690 | 417.124 | 374.057 | 348.738 | 192.112 |
| sieve / 100000 | 1 | 18.054 | 11.853 | 16.880 | 13.232 | 6.235 |
| sieve / 100000 | 2 | 18.013 | 11.858 | 16.777 | 13.183 | 6.177 |
| minimal / 100000 | 1 | 28.048 | 27.974 | 22.284 | 18.172 | 7.842 |
| minimal / 100000 | 2 | 28.380 | 27.976 | 22.165 | 18.445 | 7.747 |
| memset / 100000 | 1 | 13.508 | 14.194 | 9.724 | 8.472 | 4.308 |
| memset / 100000 | 2 | 13.410 | 14.043 | 9.854 | 8.512 | 4.321 |

Constructor CPU microseconds below are order 1/order 2. Prepared construction still
reserves a 131,072-byte empty index with no decoded operations; lazy work belongs to
cold execution. These small constructor observations do not establish a constructor
speed gain. Complete PolkaVM module/instance construction is not measured.

| Guest | ABI baseline constructor | Operand constructor | Existing complete gas plan |
|---|---:|---:|---:|
| pinky | 6.472/4.549 | 5.180/6.512 | 3041.294/3038.480 |
| sieve | 6.592/8.295 | 5.490/6.492 | 14442.084/14489.163 |
| minimal | 58.799/59.741 | 59.291/56.055 | 45.024/39.524 |
| memset | 10.489/11.011 | 10.580/11.211 | 263.792/263.461 |

Fourth-call counters exclude three warmups. Ir is executed native instructions, not
guest opcodes. Bcm/Bim are simulated conditional/indirect branch misses, not hardware
measurements. Data/instruction cache simulation remains disabled.

| Guest | Reused native instructions (ABI → operands) | Cold Ir change | Reused Ir change | Conditional misses | Indirect misses | Combined miss change |
|---|---:|---:|---:|---:|---:|---:|
| pinky | 3662.509M → 3288.025M | -9.95% | -10.22% | 24.579M → 23.154M | 28.450M → 28.450M | -2.69% |
| sieve | 96.193M → 85.081M | -0.61% | -11.55% | 0.207M → 0.301M | 1.131M → 1.131M | +6.99% |
| minimal | 323.310M → 291.510M | -9.80% | -9.84% | 2.800M → 2.100M | 1.900M → 1.900M | -14.89% |
| memset | 133.370M → 120.766M | -8.89% | -9.45% | 0.301M → 0.101M | 1.100M → 1.100M | -14.26% |

Indirect misses are essentially unchanged. Sieve gets faster despite 6.99% more
combined simulated misses; the improvement is not evidence that indirect prediction
has been fixed. Lower native instruction counts and smaller retained records support
the operand-consumption hypothesis, without proving the hardware-level cause.

Resident block/operation counts, hits, preparation totals and evictions are unchanged
between endpoints in both orders. Resident bytes and transient peaks shrink:

| Guest | Resident blocks / operations | Resident bytes ABI → operands | Peak bytes ABI → operands | Evictions after 13 calls |
|---|---:|---:|---:|---:|
| pinky | 792 / 5,911 | 682,920 → 493,768 | 709,360 → 510,608 | 751 |
| sieve | 991 / 13,226 | 1,334,600 → 911,368 | 1,361,216 → 928,320 | 615 |
| minimal | 9 / 59 | 136,624 → 134,736 | 159,152 → 149,072 | 0 |
| memset | 63 / 365 | 165,712 → 154,032 | 188,240 → 168,368 | 0 |

Pinky still incurs 58 evictions per repeated call and sieve 48; minimal and memory
fill have none. This experiment reduces storage without changing replacement policy.

The candidate takes 1.33–1.34× PolkaVM interpreted CPU for sieve, 2.38–2.41× minimal,
2.00–2.03× memory fill and 1.91–1.93× Pinky in this run. Existing dynamic/planned
paths share the candidate image; the matched baseline executable was timed only in
prepared mode. Thus this run does not independently isolate ordinary-path code-layout
effects. The results qualify this optional prepared change on these inputs and this
runner, not complete JAM parity or performance on every CPU/program. No further
optimization or default-engine switch is included in this increment.

## Segment position bookkeeping trial

This bounded fourth stack layer starts from accepted operand parent
`7115dfd067c882577230bc3ba3bc6806de8d3a34`. In that parent's fourth-call profiles,
execution-owner/loop/cache self instruction shares are 31.92% Pinky, 55.00% sieve,
21.92% minimal and 41.41% memory fill. Checked loads/stores account for 40.58%,
19.96%, 56.15% and 34.58%, respectively. Generated-C lines writing ordinary next PCs
account for 2.44%, 2.87%, 1.75% and 1.99%; these attribution counts are not CPU shares.

The existing operation index becomes authoritative within a prepared segment. Each
immutable segment stops at its first block terminator, so its iteration endpoint can
be bounded once by the available operation count and remaining attempt budget. The
inner loop no longer retests a separate ended flag or remaining counter, and ordinary
handlers do not maintain a parallel byte PC. Segment/budget boundaries materialize
the physical successor; control transfers retain their selected target. Fault/host
publication reconstructs the causing byte PC from the selected immutable operation;
terminal exits retain recursive normalization. No external callback can observe stale
CPU coordinates. Partial guest exits debit only their attempted prefix before host
response processing; local failures still carry no published machine state.

Acceptance requires complete opcode/reference/host/fault/ownership parity, independent
PC witnesses across segment and callback boundaries, exact attempt and host budgets,
all maintained guests versus the parent, and the same paired Linux cold/reused
comparison. Pricing, memory checks, sparse cache policy, record layout, public APIs
and handler ABI remain unchanged. No speed gain is claimed before qualification.
