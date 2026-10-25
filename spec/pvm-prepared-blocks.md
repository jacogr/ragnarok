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

## Segment position bookkeeping trial (rejected)

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

Local validation passes the complete 139-opcode/host/cache/ARC suite, including 30
host-budget/attempt combinations with independently known callback PCs/registers,
fault reconstruction and paid repair after a segment split, and exact next-block
out-of-gas coordinates. Mixed reference and host execution suites pass. All seven
maintained guest/size cases pass in both process orders against the accepted parent;
fresh compiler caches and identical candidate rebuild controls pass. Formatting,
63 affected Python safeguards, and semantic checks for all 441 production modules
plus the peer entry point pass. Only explanatory comments differ from the tested
native snapshot; Linux exact-head instruction counts and CPU timings remain pending.

## Rejected segment-position result (2026-10-25)

Reject the combined bounded-prefix/deferred-PC runtime experiment. Sieve improves by
4.41–5.80%, but minimal regresses by 2.36–4.00% in both process orders. Minimal 1000
also regresses by 1.13–1.81%. Pinky improves only 1.04–1.29%, with overlapping sample
ranges; memory fill improves 1.50–2.57%. Those small improvements do not justify the
minimal regression. Restore the runtime byte-for-byte to accepted operand parent
`7115dfd067c882577230bc3ba3bc6806de8d3a34`, retaining the independent segment,
PC, host-attempt, fault/retry and next-block gas boundary witnesses. No narrower
PC-only or alternate loop variant is accepted or started in this increment.

[Linux run 40208591265](https://github.com/jacogr/ragnarok/actions/runs/40208591265)
measured rejected trial `e2d7afec7c2099059ecc737be518e0236907da2c` against that
accepted parent. Runner: AMD EPYC 7763, Linux x86-64, pinned Nimony nightly 4724f66,
checked ARC/Clang ThinLTO. Timings below belong to the rejected head, not the restored
runtime. Use the same-runner baseline column for the retained prepared implementation.

Correctness/measurement qualification passed: native complete opcode/host/budget
suite, all 70 process runs (13 fresh-state calls each), 24 profiles and four collection
controls. Every execution checked terminal CPU, all registers, gas, all mapped page
bytes and permissions, and original source immutability. Both assertion probes had
their expected failures. Fresh compiler-cache and byte-identical independent candidate
rebuild controls passed. Tracked sources match exact revision hashes; downloaded
generated-source/profile hashes and single-execution scopes were independently
verified. All 70 raw process outputs reproduce report sample and cache metadata.

Reused CPU milliseconds are medians of ten calls after three warmups. Order 1 is
dynamic, planned, trial prepared, baseline prepared, PolkaVM; order 2 reverses it.

| Guest / size | Order | Dynamic | Planned | Retained operands | Rejected position trial | PolkaVM interpreted | Trial CPU change |
|---|---:|---:|---:|---:|---:|---:|---:|
| pinky / 1 | 1 | 497.913 | 413.610 | 355.950 | 351.372 | 188.747 | -1.29% |
| pinky / 1 | 2 | 471.730 | 410.654 | 345.304 | 341.708 | 189.944 | -1.04% |
| sieve / 100000 | 1 | 17.383 | 10.701 | 7.303 | 6.880 | 5.549 | -5.80% |
| sieve / 100000 | 2 | 17.458 | 10.622 | 7.248 | 6.929 | 5.579 | -4.41% |
| minimal / 100000 | 1 | 28.195 | 26.028 | 17.988 | 18.708 | 7.461 | +4.00% |
| minimal / 100000 | 2 | 28.168 | 27.850 | 17.965 | 18.389 | 7.494 | +2.36% |
| memset / 100000 | 1 | 13.498 | 13.447 | 8.307 | 8.094 | 4.190 | -2.57% |
| memset / 100000 | 2 | 13.526 | 13.399 | 8.444 | 8.318 | 4.186 | -1.50% |

Cold CPU milliseconds below are single sample-0 observations including lazy preparation,
not repeated cold medians. Construction, state restoration and reference comparisons
are outside execution timing.

| Guest / size | Order | Cold dynamic | Cold planned | Cold retained operands | Cold rejected trial | Cold PolkaVM |
|---|---:|---:|---:|---:|---:|---:|
| pinky / 1 | 1 | 482.292 | 405.993 | 348.390 | 353.999 | 193.800 |
| pinky / 1 | 2 | 465.056 | 408.814 | 348.341 | 334.395 | 189.455 |
| sieve / 100000 | 1 | 17.925 | 11.407 | 13.234 | 12.778 | 6.212 |
| sieve / 100000 | 2 | 17.969 | 11.395 | 13.099 | 12.837 | 6.203 |
| minimal / 100000 | 1 | 29.432 | 27.310 | 18.155 | 18.240 | 7.566 |
| minimal / 100000 | 2 | 29.532 | 28.842 | 18.126 | 18.624 | 7.658 |
| memset / 100000 | 1 | 13.827 | 13.542 | 8.474 | 8.265 | 4.344 |
| memset / 100000 | 2 | 13.562 | 13.350 | 8.464 | 8.376 | 4.327 |

Constructor CPU microseconds are order 1/order 2. Prepared construction creates the
same empty 131,072-byte index, with no operations; lazy work belongs to cold execution.
No constructor improvement is established. PolkaVM module/instance construction is
not measured by this harness.

| Guest | Retained operand constructor | Rejected trial constructor | Existing complete gas plan |
|---|---:|---:|---:|
| pinky | 9.638/9.888 | 4.758/9.217 | 2965.154/3007.552 |
| sieve | 9.338/4.378 | 10.309/4.348 | 14141.005/14282.349 |
| minimal | 57.788/59.382 | 57.958/60.864 | 34.124/34.795 |
| memset | 7.114/6.653 | 6.682/6.663 | 255.698/255.709 |

Fourth-call instruction counts isolate one execution after three warmups. Ir means
executed native instructions, not guest opcodes. Conditional/indirect branch misses
are simulated, not hardware counters. Data/instruction cache simulation is disabled.

| Guest | Reused native instructions (retained → trial) | Cold Ir change | Reused Ir change | Conditional misses | Indirect misses | Combined miss change |
|---|---:|---:|---:|---:|---:|---:|
| pinky | 3288.025M → 3081.311M | -6.23% | -6.29% | 23.154M → 27.098M | 28.450M → 28.450M | +7.64% |
| sieve | 85.081M → 79.520M | -3.36% | -6.54% | 0.301M → 0.277M | 1.131M → 1.131M | -1.64% |
| minimal | 291.510M → 277.810M | -4.69% | -4.70% | 2.100M → 2.400M | 1.900M → 1.900M | +7.50% |
| memset | 120.766M → 115.264M | -4.48% | -4.56% | 0.101M → 0.301M | 1.100M → 1.100M | +16.62% |

Lower instruction counts did not deliver a broad CPU win. Conditional misses rise
for minimal, memory fill and Pinky while indirect misses stay essentially unchanged.
This is a diagnostic clue, not proof of the hardware cause. The loop transformation
and deferred PC writes were measured together; neither sub-change is independently
qualified by this result.

All prepared-cache observations match exactly between retained and rejected endpoints,
including resident/peak bytes, hits, preparation totals and evictions, in both orders:

| Guest | Resident blocks / operations | Resident bytes | Peak bytes | Evictions after 13 calls |
|---|---:|---:|---:|---:|
| pinky | 792 / 5,911 | 493,768 | 510,608 | 751 |
| sieve | 991 / 13,226 | 911,368 | 928,320 | 615 |
| minimal | 9 / 59 | 134,736 | 149,072 | 0 |
| memset | 63 / 365 | 154,032 | 168,368 | 0 |

Pinky still has 58 evictions per repeated call, sieve 48; minimal and memory fill have
none. The trial provided no cache occupancy/churn improvement.

Same-runner retained operands take about 1.82–1.89× PolkaVM interpreted CPU for Pinky,
1.30–1.32× sieve, 2.40–2.41× minimal and 1.98–2.02× memory fill. Existing dynamic
and planned paths share the trial image; only the prepared path has a separately
timed matched baseline. This run does not isolate ordinary-path code-layout effects
or establish performance on other CPUs/programs. The accepted earlier operand/ABI
improvements remain intact; no default-engine switch or further optimization follows
from this rejected experiment.

Restoration verification passes the full prepared opcode/host/PC/attempt/fault/cache
suite with all retained new boundary witnesses and 1000 balanced ARC lifetimes.
All seven guests pass both zero-clock process orders against the parent. Their matched
runtime/driver source manifests are identical, and independent fresh builds produce
byte-identical baseline/candidate images. Final formatting checks pass. No new timing
claim is made for the restored head; its runtime is the accepted operand baseline.

Fewer checks/writes and lower Ir do not guarantee lower CPU time. This trial also adds
per-segment endpoint/accounting work and changes the generated loop's branch/layout
behavior. More simulated conditional misses are a clue; identifying the actual cause
would require hardware counters and assembly analysis. [Valgrind's documentation](https://valgrind.org/docs/manual/cg-manual.html)
distinguishes reproducible instruction counts from variable execution time and warns
that its basic branch/cache simulations do not model modern hardware closely. The
PC-deferral and bounded-loop changes were tested together; this result does not prove
that a narrower PC-only change would regress or improve runtime.

## JITB — Just In Time Blocks

This fifth stack layer starts from `58cb51e90eaec06de3c97546573055bb9097e5a3`;
its runtime is the accepted operand implementation, with additional boundary tests.
JITB prepares a block on its first visit and reuses its executable stream until the
bounded cache evicts it. This is interpreted execution: selected native handler
functions execute guest operations; no guest-specific native code is generated.
The goal is a complete independently implemented execution-stream model, inspired by
the pinned reference's handler/offset dispatch, preserving the existing GP contracts.

A 32-bit private offset identifies a sparse cache slot and a node within its bounded
block. Blocks are prepared lazily and own parallel handler, 16-byte argument and
source-site arrays. Pricing and segment bridging are synthetic stream nodes; only
guest handlers consume scheduling attempts. Every source-site retains its full-width
guest address, exact span and source-derived validation facts. Static links validate
the cached destination's exact guest-PC tag before selecting its offset, so cache
replacement cannot turn an old link into a different instruction. Blocks contain no
references to other blocks and no mutable machine/callback state; invocation and host
continuation references keep only their active block alive.

Handlers receive the invocation frame plus offset and return the next offset. Rare
errors/guest exits are recorded in the invocation, with a reserved stop offset.
Public prepared owners, source identity, bounds checks, whole-block gas semantics,
mutable-memory workspace and immutable publication boundaries remain intact. No
source-pin or compiler change is included. Full opcode, host/fault/retry, budget,
cache replacement and ARC parity must pass before paired Linux timings and profiles.
Construction, cold/reused execution, both process orders and PolkaVM interpreted
remain separate evidence. Performance benefit is unproven until measured.

Local checked ARC/Clang ThinLTO validation passed the full 139-opcode prepared suite,
mixed-program reference and host-execution suites, plus the seven maintained guest/
size cases against both current interpreters, the accepted prepared parent and
PolkaVM interpreted in both process orders. Checks include complete reference state,
source snapshots, one-slot replacement, high internal offsets, full-width immediate
bits and 1000 balanced owner lifetimes. The pinned backend required explicit returns
in the final compile-time control alternative plus a trailing statement-position
sentinel; neither compiler sources nor pins were changed.

Arguments occupy 16 bytes, source sites 16 bytes and handler pointers 8 bytes on
64-bit targets. Each block also retains two synthetic nodes and a larger header;
these overheads are included in cache accounting. Smaller arguments alone do not
establish a smaller total cache or a performance gain. Linux paired CPU timings and
profiles are recorded below.

### Linux qualification: full JITB model

Run [40212798836](https://github.com/jacogr/ragnarok/actions/runs/40212798836) passed at
candidate `34d26b5f4e6c186d56be9c9e24c059966b6478f6` against accepted runtime parent
`58cb51e90eaec06de3c97546573055bb9097e5a3` on an AMD EPYC 7763, Linux x86_64,
with checked ARC/Clang ThinLTO. Exact source, generated-source and selected-profile
hashes verified; fresh private compiler caches and the repeated candidate image
control passed. All 70 processes × 13 fresh-state samples, 24 single-execution
profiles, four collection controls, both assertion controls and the exact-head
native prepared suite passed. Complete registers, gas, mapped page bytes, permissions
and immutable-source checks ran outside the timing regions.

**Verdict: correctness passed; performance qualification failed.** JITB reused
execution regresses on every large guest in both orders, with nonoverlapping
baseline/candidate sample ranges. Keep this layer explicitly experimental for
design/profile review; the accepted prepared parent remains the performance target.
No default change or merge is justified by this run. The smaller stream ABI alone
does not establish a faster execution model.

Order 1 is dynamic → planned → JITB → baseline → PolkaVM; order 2 reverses it.
Reused CPU is the median of ten samples after three warmups, all in milliseconds.

| Guest | Order | Dynamic | Planned | Baseline prepared | JITB | PolkaVM interpreted | JITB change |
|---|---:|---:|---:|---:|---:|---:|---:|
| Pinky | 1 | 459.069 | 431.505 | 343.108 | 388.942 | 181.321 | +13.36% |
| Pinky | 2 | 456.732 | 395.671 | 346.527 | 389.275 | 183.315 | +12.34% |
| Sieve | 1 | 17.537 | 11.114 | 7.401 | 8.877 | 5.562 | +19.94% |
| Sieve | 2 | 17.668 | 11.141 | 7.282 | 8.887 | 5.529 | +22.04% |
| Minimal | 1 | 27.052 | 27.384 | 17.992 | 20.597 | 7.487 | +14.48% |
| Minimal | 2 | 27.014 | 26.755 | 17.989 | 20.625 | 7.513 | +14.65% |
| Memory fill | 1 | 13.073 | 14.704 | 8.325 | 9.606 | 4.408 | +15.39% |
| Memory fill | 2 | 12.967 | 11.959 | 8.289 | 9.475 | 4.182 | +14.30% |

Cold is one first invocation, including lazy preparation and excluding constructor
cost. These are observations, not medians or standalone cold-speed claims.

| Guest | Order | Dynamic cold | Planned cold | Baseline cold | JITB cold | PolkaVM cold |
|---|---:|---:|---:|---:|---:|---:|
| Pinky | 1 | 450.731 | 435.086 | 337.470 | 379.068 | 183.960 |
| Pinky | 2 | 453.805 | 393.176 | 344.484 | 387.228 | 183.779 |
| Sieve | 1 | 18.077 | 11.762 | 13.590 | 15.008 | 6.192 |
| Sieve | 2 | 18.132 | 11.542 | 13.128 | 15.006 | 6.176 |
| Minimal | 1 | 28.044 | 27.777 | 18.289 | 21.010 | 7.571 |
| Minimal | 2 | 28.076 | 27.888 | 18.286 | 20.936 | 7.530 |
| Memory fill | 1 | 13.088 | 14.731 | 8.585 | 9.738 | 4.347 |
| Memory fill | 2 | 13.130 | 12.071 | 8.483 | 9.651 | 4.290 |

Constructors are separate single CPU observations in microseconds, order 1 / 2.
PolkaVM module/instance setup is outside execution timing and is not timed by this
harness; do not interpret the missing constructor measurement as zero.

| Guest | Planned constructor | Baseline constructor | JITB constructor |
|---|---:|---:|---:|
| Pinky | 3050.80 / 3048.89 | 7.17 / 4.58 | 4.79 / 6.43 |
| Sieve | 14539.54 / 14961.11 | 4.43 / 4.04 | 5.08 / 4.45 |
| Minimal | 35.52 / 35.35 | 58.32 / 57.85 | 58.92 / 57.26 |
| Memory fill | 248.67 / 256.41 | 7.19 / 7.16 | 6.19 / 11.36 |

Profiles count executed native instructions (`Ir`) and both simulated branch-miss
classes. These are not hardware branch-miss measurements; the run does not collect
hardware cycles, cache misses or prove the CPU cause of any regression. Counts below
are baseline → JITB, in millions. Cold/reused each select exactly one execution.

| Guest | Phase | Native instructions | Conditional misses | Indirect misses |
|---|---|---:|---:|---:|
| Pinky | cold | 3318.299 → 3719.703 | 23.389 → 22.423 | 28.471 → 33.841 |
| Pinky | reused | 3288.025 → 3699.804 | 23.154 → 22.180 | 28.450 → 33.820 |
| Sieve | cold | 165.459 → 173.380 | 0.937 → 0.776 | 1.183 → 1.537 |
| Sieve | reused | 85.081 → 106.058 | 0.301 → 0.121 | 1.131 → 1.485 |
| Minimal | cold | 291.836 → 316.317 | 2.103 → 2.203 | 1.900 → 2.200 |
| Minimal | reused | 291.510 → 316.110 | 2.100 → 2.200 | 1.900 → 2.200 |
| Memory fill | cold | 122.712 → 142.589 | 0.115 → 0.216 | 1.102 → 1.502 |
| Memory fill | reused | 120.766 → 141.470 | 0.101 → 0.201 | 1.100 → 1.500 |

Cache diagnostics match in both orders. Retained bytes include index, headers,
all arrays and synthetic nodes; operation counts refer only to guests.

| Guest | Resident blocks / guest ops | Retained bytes baseline → JITB | Extra evictions per reused call |
|---|---:|---:|---:|
| Pinky | 792 / 5911 | 493,768 → 494,232 | 58 |
| Sieve | 991 / 13226 | 911,368 → 818,672 | 49 |
| Minimal | 9 / 59 | 134,736 → 134,872 | 0 |
| Memory fill | 63 / 365 | 154,032 → 155,752 | 0 |

The profiles explain where native work moved, rather than proving a hardware stall
cause. Central dispatch self-instructions fell, but new `preparedEnter` and synthetic
`preparedCharge` self-work consumes respectively 6.43% / 3.71% of Pinky,
15.01% / 8.68% of sieve, 4.27% / 2.47% of minimal and 12.73% / 7.35% of memory
fill. Per-guest handlers also execute more self-instructions while indexing arguments
and sites. Generated C confirms per-entry ARC retention/release and checked operand
and site lookups; the profile cannot separately attribute all their optimized costs.

Checked scalar load/store self-instruction totals are exactly unchanged in all four
guests. Their shares are now 36.07%, 16.01%, 51.79% and 29.53% respectively; shares
fall because other work grew. Repricing is still a small residual and cache churn
did not improve. Reducing the main-loop share alone hid displaced work.

Next bounded investigation: keep the lazy block model but inspect block-transition
ownership and redundant parallel-array lookups together with their generated code.
Compare passing the already selected immutable node/argument to a handler against
re-fetching it through the frame; keep compact source sites for observable exits.
Measure synthetic charge dispatch overhead before deciding whether price handling
belongs in every cached entry. Preserve checked accesses, exact links, whole-block
gas, fault retry, callback/attempt boundaries and source ownership throughout.
A separate later memory-path investigation remains useful; no such optimization is
mixed into this qualification commit.
