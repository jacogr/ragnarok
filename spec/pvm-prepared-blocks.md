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


## Exact-tagged scalar successor hints, 2026-10-25

Each prepared segment may remember the last successfully resolved successor PC
and an index-plus-one into its owner's bounded slot array. Zero means unlearned.
Hints contain no destination reference, handler pointer or operation index. They
cannot form an ownership cycle or retain evicted payloads. The existing
invocation-owned current segment survives a transfer so its hint can be inspected
without adding another retained predecessor owner. A failed hint uses the original
`preparedChunk` path; only successful resolution learns a destination.

A hint is never authority. Before using it, execution checks the successor PC,
index bounds, current resident owner and its exact start PC. The owning program
and policy are fixed; a same-PC replacement in that slot is therefore a genuine
current segment for the same source. No saved address requires generation-based
pointer validation. Evicted, displaced, absent and changed-PC targets fall back
to normal lookup/preparation. Host continuations, whole-block pricing, instruction
attempts, checked memory, operation records and handlers retain their existing
semantics. Hints are exclusive-worker mutable facts under the existing busy guard.

The header grows by 16 bytes on the measured arm64 target. Its actual `sizeof`
enters the existing minimum-payload admission, segment capacity, resident-byte,
peak-byte and eviction accounting; storage ceilings and policies do not change.
For the maintained guests, every block/operation/hit/eviction observation matches
the baseline. Resident and peak bytes include the additional header payload.

The prepared suite retains all 139-opcode, segment, gas, attempt, host/refusal and
fault checks. An additional two-slot witness learns a path, executes a different
marked entry that replaces its destination with a different register result, and
reruns the original path. Repeated calls compare every CPU field, memory byte and
permission with dynamic execution, including low-gas and attempt limits. The
witness joins the existing 1,000 balanced ARC lifetime cycles.

The inner loop borrows its active segment from the invocation-owned `chunk`;
that owner remains unchanged until the iteration ends. The closed private handler
set receives frame/operation facts and cannot mutate that local owner or the
cache slots. No extra retain/release is needed for `active` on every segment.
Cache replacement still uses the original owned current segment, and publication
still stores an owned location before application callbacks. No borrow crosses a
cache mutation or escapes a callback boundary. The full prepared/eviction/host/gas
suite also passes checked AddressSanitizer with 1,000 balanced lifetime cycles.

### Qualified local comparison

The actual PR base is scalar-window PR #1679 at
`01c4ee54525f645a0f6e434db5b27c754ef7f59b`. Current master for this comparison is
`ea55b04d60bc8d3113d1dcac3cb537dfe57c7fab`. The final measured/promoted
`src/pvm/step.nim` SHA-256 is `c2d39e6cde2a136da51e047937af41020cbdc6c0ec6bacfc3e4d66e164f2f737`.
Pinned Nimony 4724f66c, ARC/Clang 21 checked release/speed with ThinLTO, Apple M1 Max.
Every endpoint compiles through identical source/cache/output paths from fresh
private caches. The repeated candidate image is byte-identical; rebuilding it
after the master/base controls produces that same image again.

The final 70-process comparison covers all seven maintained guest/size cases in
both process orders, thirteen calls per process: three warmups, then ten measured
CPU samples. All registers, gas, terminal state, page bytes/permissions and source
snapshots pass. Wrong expected gas is rejected before a successful timing row for
master, the actual PR base and the candidate. Earlier 112-process isolated link
and 112-process active-borrow comparisons remain separate local evidence; two
unsuccessful memory/hint trials were rejected without production changes.

CPU milliseconds below are reused medians, forward / reverse process order:

| Guest | Master prepared | #1679 prepared | This implementation | Learning port | Rust interpreted, reused |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 203.766 / 203.044 | 179.427 / 180.035 | 168.244 / 168.486 | 98.092 / 98.107 | 95.421 / 95.465 |
| sieve | 6.088 / 6.131 | 5.848 / 5.840 | 4.915 / 4.931 | 3.540 / 3.554 | 3.649 / 3.602 |
| minimal | 14.032 / 14.008 | 11.650 / 11.745 | 11.464 / 11.492 | 6.490 / 6.540 | 6.199 / 6.178 |
| memset | 6.505 / 6.504 | 6.391 / 6.472 | 5.051 / 5.006 | 3.791 / 3.773 | 3.958 / 3.982 |

Against the actual PR base, Pinky uses about 6% less CPU, sieve 15.5–16.0% and
fill 21.0–22.6%; minimal's small change remains unproven. Against master, the whole
stack reduces CPU by about 17% Pinky, 19–20% sieve, 18% minimal and 22–23% fill. These
are same-session comparisons, not percentages compounded from separate sessions.
The isolated active borrow reduces fill CPU by 19.5–19.8% in both process orders;
Pinky/minimal changes in that isolated trial remain unproven.

Every block/operation/hit/eviction observation matches the actual PR base;
resident/peak bytes include the larger successor headers. A separate clock-disabled
four-call diagnostic copy validates hints that skip 4,338,676/5,285,285 normal
lookups on Pinky, 253,436/353,857 on sieve, 200,002/300,005 on minimal and
400,050/400,059 on fill. These software counts are not preparation misses or
hardware instruction/cache/branch measurements. The diagnostic counters are
absent from the measured and promoted implementation.

Constructors and individual first-cold-owner calls stay separate from reused
medians in the raw records. Constructor CPU brackets only the bounded empty
prepared owner; program/initial-memory capture remains outside execution timing.
Ragnarök creates fresh invocation memory staging inside each call; Rust's public
reuse adapter resets input outside its execution clock. The learning port covers
the maintained executed core, with predecoded/priced facts outside timing and an
unbounded cache. It is an architectural control, not a complete interpreter or
total lifecycle equivalent. The target of beating the port/Rust is not reached.

Local records live under `build/pvm-port-lab/prepared-active-borrow`: isolated and
cumulative JSON/raw logs, exact source snapshots, fresh-cache build controls,
generated C, native and AddressSanitizer evidence. The earlier link-only record is
under `prepared-links`. No translated core or diagnostic instrumentation ships
with this feature. No Linux timing or hardware counter claim is made here.


## Constant-width checked writer execution, 2026-10-25

Prepared memory handlers already know their access width. Carry that fact through
invocation staging into `load[Width]` / `store[Width]` on the scalar writer. Runtime
width calls and fixed-width calls instantiate the same private implementation;
only the byte count becomes constant. Unsupported constants fail the ordinary
checked precondition. The runtime surface retains its existing error ordering.

All owner, permission, physical-endpoint, protected-prefix, COW, alias and snapshot
checks remain. Immutable memory access and ordinary interpreter behavior retain
their existing paths. Handler ABI, 56-byte records, pricing, attempts, PC writes,
cache policy/limits and ownership are unchanged. Generated C contains explicit
1/2/4/8-byte writer specializations alongside the runtime-count specialization.
This supplies compiler knowledge rather than disabling a check or replacing memory.

The scalar-window suite adds differential fixed-width nil, chunk/page, read-only,
missing/protected/wrapped/physical-endpoint and three-epoch alias witnesses. Exact
constant-invalid load/store compiler rejections join the existing guard runner.
Nine local native suites, four independent references, AddressSanitizer on all
prepared opcodes/host/budget/eviction cases and ARC 1,000 pass. The promoted scalar
window, prepared and independent mixed reference suites pass through Make;
inventory, positive privacy controls and exact rejection evidence are retained.

### Qualified local CPU comparison

Measured parent #1683: `5e8e04fbf49413751e96a808a24a2a9f13e541f0`. Master: `ea55b04d60bc8d3113d1dcac3cb537dfe57c7fab`.
Final `step.nim` SHA-256: `44590800fca26dcb0eddbc025e8a3a87415d4da55e802762e0913bdbbe09b398`;
`machine.nim`: `0f5392ee189aac3321c50cf817edb0a6b33d0fe7788a36b22c08fc6aa183f152`.
Pinned Nimony 4724f66c, checked ARC/Clang 21 release/speed/ThinLTO on Apple M1 Max.
Fresh private compiler caches use identical source/cache/output paths for each
endpoint. Candidate repeats are byte-identical; the final precondition-based valid
code image also matches the initial trial, and rebuilding after master/parent
controls reproduces the same image. No compiler/dependency changes are used.

Initial and final isolated comparisons each contain 112 processes. The fresh
cumulative comparison contains 70; an additional 48 alternating confirmation
processes cover all four large cases. Each process makes 13 full-state calls:
three warmups and ten measured CPU samples. All registers, gas, terminal state,
every mapped page byte/permission and source snapshots pass. Wrong gas references
are rejected before successful timing output. All seven maintained guest/size
cases participate in the full comparisons. Constructors and cold calls remain
separate from reused execution. This is local evidence, not exact-head Linux CI.

Reused CPU milliseconds, **forward / reverse process order**, from the final
same-session cumulative comparison:

| Guest | Master prepared | Parent #1683 | This implementation | Learning port | Rust interpreted, reused |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 196.367 / 196.300 | 162.099 / 161.348 | 153.384 / 153.440 | 94.485 / 94.211 | 91.851 / 92.115 |
| sieve | 5.929 / 5.979 | 4.777 / 4.733 | 4.661 / 4.692 | 3.507 / 3.503 | 3.503 / 3.492 |
| minimal | 13.610 / 13.569 | 11.154 / 11.040 | 9.776 / 9.800 | 6.300 / 6.469 | 6.064 / 5.992 |
| memset | 6.251 / 6.367 | 4.823 / 4.918 | 4.660 / 4.679 | 3.644 / 3.645 | 3.845 / 3.936 |

The independent runtime/planned controls below belong to the final isolated
comparison, not the separate cumulative session above. CPU milliseconds:

| Guest | Dynamic control | Planned control | Parent prepared | This implementation |
| --- | ---: | ---: | ---: | ---: |
| pinky | 296.525 / 295.899 | 284.188 / 283.346 | 161.680 / 161.216 | 154.293 / 160.399 |
| sieve | 12.294 / 12.216 | 8.476 / 8.504 | 4.904 / 4.694 | 4.711 / 4.671 |
| minimal | 16.564 / 16.545 | 16.218 / 16.635 | 11.042 / 11.029 | 9.745 / 9.730 |
| memset | 8.789 / 8.774 | 8.471 / 8.505 | 4.821 / 4.825 | 4.638 / 4.636 |

Median CPU change across six alternating confirmation pairs (candidate/parent):

- pinky: -4.55% (pair range -5.78% to -3.69%).
- sieve: -0.92% (pair range -1.19% to -0.09%).
- minimal: -11.89% (pair range -12.22% to -11.32%).
- memset: -3.54% (pair range -3.86% to -3.00%).

Keep this change for the useful minimal/fill gains without a material measured
regression. Pinky improves in most pairs, with one final isolated pair within
noise; its size varies between sessions. Sieve changes remain unproven. No
percentage is compounded from separate sessions. The learning port/Rust gap
remains: this change does not establish parity or the target of being faster.

Cold CPU milliseconds are single first-call observations, including lazy
preparation, not repeated cold medians:

| Guest | Master cold | Parent cold | This implementation cold | Port cold | Rust cold |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 200.929 / 196.221 | 164.204 / 162.910 | 154.703 / 154.724 | 94.769 / 94.502 | 93.442 / 93.417 |
| sieve | 9.864 / 10.155 | 8.723 / 8.678 | 8.810 / 8.633 | 3.555 / 3.563 | 6.078 / 6.098 |
| minimal | 13.589 / 13.591 | 11.135 / 11.465 | 9.836 / 9.845 | 6.428 / 6.250 | 6.034 / 6.125 |
| memset | 6.343 / 6.376 | 4.966 / 4.969 | 4.977 / 4.782 | 3.669 / 3.684 | 4.007 / 4.020 |

Constructor CPU microseconds bracket only creation of the empty bounded prepared
owner; program/initial-memory capture remains outside execution timing. No
constructor improvement is established. Port/Rust constructors are not measured:

| Guest | Master constructor | Parent constructor | This implementation constructor |
| --- | ---: | ---: | ---: |
| pinky | 5.000 / 5.000 | 5.000 / 5.000 | 5.000 / 5.000 |
| sieve | 5.000 / 5.000 | 6.000 / 5.000 | 6.000 / 5.000 |
| minimal | 14.000 / 15.000 | 12.000 / 15.000 | 11.000 / 11.000 |
| memset | 8.000 / 7.000 | 5.000 / 7.000 | 6.000 / 7.000 |

Every prepared block/operation/hit/eviction and resident/peak-byte observation
matches the parent for all calls. Record size, cache occupancy and churn do not
change. These software observations are not hardware cache/branch misses. No new
native instruction-count or hardware-event claim is made. A separate one-second
statistical baseline stack sample, excluded from timings, records 750 engine
samples, including 110 scalar-load and 73 scalar-store self samples; this guided
the hypothesis, not the quantified performance verdict.

Ragnarök creates fresh invocation staging inside each execution clock. Rust's
public reuse adapter restores input outside that clock. The learning port covers
the maintained executed core using predecoded/priced input facts and an unbounded
cache; it is an architectural control, not full JAM/lifecycle parity. Frozen port
and Rust binaries are included in both orders; no translated implementation ships.

Local provenance, all samples/spreads, constructors/cold calls, source/generated-C
hashes, equal-image controls, exact compiler rejections and verification logs live
under `build/pvm-port-lab/prepared-static-widths`. Rejected resident-borrow, direct
switch and packed-result experiments remain ignored laboratory evidence, with no
production changes or PRs. The independent memory implementation remains checked.


## Stable prepared-loop facts, 2026-10-26

Borrow the immutable operation-sequence metadata from the unchanged invocation-owned
segment. Closed private handlers cannot mutate that array or the owning local;
cache replacement occurs outside the iteration, and host publication retains its
owned location before returning. The generated C copies metadata without retaining
or destroying another sequence owner. No borrow crosses an application callback.

Preparation stops immediately after a terminator, so only the final retained
operation can end a block. The existing array-length bound already stops there;
remove the redundant `ended` consumer flag. Keep the record flag/layout unchanged.
Read the immutable causing PC only on a genuine nonterminal exit, from the checked
just-executed element `at-1`; terminal exits still normalize to zero. Ordinary PC
writes, instruction-attempt debits and all checks remain at their original points.
Handler ABI, record size, cache policy/limits, pricing and memory are unchanged.

The new witness jumps over a register-changing instruction and trap to a valid
marked block. It verifies that sealed arrays cannot execute beyond a terminator,
with cold/reused, paid/unpaid and gas/attempt boundaries. Its first positive-case
gas assumption was wrong: both baseline and candidate correctly returned out-of-gas
at gas 10. The final case uses ample gas and retains low-gas comparisons. The
failure input and diagnostic logs remain local; no runtime defect was suppressed.

### Qualified local CPU evidence

Parent #1692 `0a16fb1dfd10d7f129cc7324b36a54d18c918066`; master `ea55b04d60bc8d3113d1dcac3cb537dfe57c7fab`.
Final `step.nim` SHA-256 `b5713bc96be80d1ed71d7310861adb7277bd949928725897b0334939cb0d501b`.

Pinned Nimony 4724f66c, checked ARC/Clang 21 release/speed/ThinLTO, Apple M1 Max.
Fresh private caches use identical compiler source/cache/output paths; candidate
repeats and the rebuild after master/parent controls are byte-identical. Existing
component checks remain applicable to unchanged paths; the final full 139-opcode,
host/budget/cache/eviction suite, four independent references and AddressSanitizer
pass, with ARC 1,000 balanced. The promoted prepared/mixed reference suites pass
through Make. The isolated view/end-flag/cause variants also pass the opcode suite.

Initial 84-process and final 112-process comparisons cover all seven maintained
guest/size cases in both orders. A fresh 70-process comparison includes master,
actual parent, the complete composition, frozen port and Rust interpreted reuse.
Another 72 alternating processes confirm parent/composition behavior. Each makes
13 full-state calls: three warmups then ten CPU measurements. Every register, gas,
terminal state, page byte/permission and original source snapshot passes; wrong
gas references fail before a successful timing row. No Linux/hardware claim.

Reused CPU milliseconds, **forward / reverse process order**, same-session controls:

| Guest | Master prepared | Parent #1692 | This implementation | Learning port | Rust interpreted, reused |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 196.171 / 195.921 | 157.385 / 153.300 | 148.512 / 146.923 | 94.881 / 94.264 | 91.959 / 93.091 |
| sieve | 5.875 / 5.911 | 4.664 / 4.688 | 4.533 / 4.392 | 3.437 / 3.397 | 3.509 / 3.495 |
| minimal | 13.622 / 13.611 | 9.851 / 9.838 | 9.319 / 9.319 | 6.293 / 6.292 | 5.970 / 6.025 |
| memset | 6.287 / 6.306 | 4.694 / 4.669 | 4.355 / 4.355 | 3.651 / 3.654 | 3.852 / 3.853 |

The separate final isolated comparison exposes interactions rather than assuming
each smaller source change is independently useful. CPU milliseconds:

| Guest | Parent | Array view | End flag only | View + end flag | Late cause only | Full composition |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| pinky | 156.101 / 155.680 | 152.868 / 152.811 | 154.810 / 154.633 | 149.815 / 148.966 | 155.274 / 153.183 | 149.135 / 147.363 |
| sieve | 4.651 / 4.651 | 4.500 / 4.506 | 4.675 / 4.669 | 4.504 / 4.505 | 4.650 / 4.652 | 4.380 / 4.399 |
| minimal | 9.722 / 9.866 | 9.466 / 9.633 | 9.620 / 9.767 | 9.380 / 9.432 | 9.916 / 9.785 | 9.302 / 9.261 |
| memset | 4.686 / 4.753 | 4.458 / 4.474 | 4.690 / 4.659 | 4.293 / 4.327 | 4.690 / 4.665 | 4.348 / 4.364 |

Median CPU change across six alternating confirmation pairs:

- pinky: -3.76% (range -4.29% to -2.74%).
- sieve: -5.79% (range -5.92% to -5.36%).
- minimal: -5.34% (range -8.17% to -4.81%).
- memset: -6.90% (range -7.19% to -6.87%).

Retain the complete composition: it reduces CPU across all four large cases
without a material measured regression. Individual changes interact; late cause
reads alone do not improve all workloads, and the version without them has a
slightly lower fill median but loses useful sieve/minimal improvement. The whole
composition is the measured review unit. No CPU cause is inferred from source
line count or fewer static instructions. The target of beating the port remains.

Cold CPU milliseconds are single sample-0 observations, not repeated cold medians:

| Guest | Master cold | Parent cold | Composition cold | Port cold | Rust cold |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 197.476 / 197.512 | 156.407 / 154.698 | 150.091 / 149.330 | 95.552 / 94.629 | 93.987 / 94.034 |
| sieve | 9.942 / 9.876 | 8.645 / 8.694 | 8.466 / 8.376 | 3.565 / 3.550 | 6.089 / 6.112 |
| minimal | 13.660 / 13.590 | 9.925 / 9.912 | 9.315 / 9.360 | 6.342 / 6.204 | 6.029 / 6.109 |
| memset | 6.434 / 6.430 | 4.784 / 4.800 | 4.466 / 4.464 | 3.653 / 3.661 | 4.028 / 4.040 |

Constructor CPU microseconds are recorded separately below; only the empty bounded
prepared owner is constructed inside that clock. Program/initial-memory capture
remain outside execution, and no constructor improvement is established:

| Guest | Master constructor | Parent constructor | Composition constructor |
| --- | ---: | ---: | ---: |
| pinky | 4.000 / 4.000 | 4.000 / 5.000 | 5.000 / 4.000 |
| sieve | 5.000 / 4.000 | 4.000 / 5.000 | 5.000 / 4.000 |
| minimal | 13.000 / 33.000 | 12.000 / 15.000 | 11.000 / 13.000 |
| memset | 5.000 / 7.000 | 7.000 / 6.000 | 7.000 / 8.000 |

All prepared-cache block/operation/hit/eviction and resident/peak-byte observations
match the parent in every call. These are software observations, not hardware
cache/branch misses. No new executed-native-instruction or branch-event counts are
claimed. Assembly inspection showed the existing attempt counter already in a
register, so that proposed optimization was skipped rather than reimplemented.

Ragnarök starts fresh invocation staging inside each execution clock. Rust's public
reuse adapter restores input outside its clock. The local partial port uses
predecoded/priced facts and an unbounded cache; it is not full JAM/lifecycle parity.
Port and Rust constructors are not measured. All translated code stays local.
Evidence under `build/pvm-port-lab/prepared-loop-views` includes every sample/spread,
separate constructors/cold calls, source/archive/generated-C identities, unchanged
component checks, final Make/reference/ASan logs and fresh equal-image controls.


## Bounded register prefixes, 2026-10-26

Independent optimization of the existing checked prepared interpreter; no learning-port
implementation ships. Pinned Gray Paper/JAM semantics and dependency pins are unchanged.
Immediate parent is #1693 at `6b5141257e92feec06b3418e1bdf375c4c88601d`;
same-session master is `ea55b04d60bc8d3113d1dcac3cb537dfe57c7fab`.

### Execution and ownership contract

Private handlers return one complete `distinct uint32` evaluation word. Typed error
ordinals occupy the low byte; successful words carry `StepError.None` and the full
`StepExit` in the next byte. Default zero remains `Uninitialized`. Failure construction
rejects `None`; status validates the entire encoding before exit selection. A compile-time
guard rejects enum-domain expansion beyond the reserved byte. The common loop compares
the exact continuation word; genuine errors/exits remain guarded typed results. Public
results and frame publication are unchanged; no error side channel or per-handler frame
writes are introduced.

Each of the 85 genuine register opcodes may prepare a bounded two-instruction prefix
when its original fallthrough is valid. The first shared register handler cannot produce
a guest exit; its inputs and fallthrough are sealed genuine facts. The second instruction
still uses its original checked handler and may fault, suspend, jump or terminate. The
loop reserves exactly two attempts only with two retained cells and at least two remaining
attempts. Otherwise it uses the original single-instruction handler. The second record
supplies the causing PC and continuation index on observable exits. Ordinary PC writes,
block pricing, gas, checked memory and host scheduling remain unchanged. Local failures
publish no partial state. There is no cross-segment prefix, recursive chain, raw array
pointer or borrowed lifetime across a callback.

For add-immediate-64 (opcode149), preparation selects one of 139 literal second-opcode
specializations. A canonical original-handler table is shared with ordinary preparation;
all arithmetic, control and memory semantics remain in the existing helpers. Selection
uses genuine opcode identities, never benchmark addresses/values. Other register prefixes
use a bounded transfer to the original second handler. Correctness does not require a
compiler tail-call optimization. Checked M1 native output has 85 bounded tail transfers
for generic prefixes and 139 literal add-prefix functions with no indirect call/lookup
inside those functions. These are static code observations, not executed instruction
counts or hardware-event measurements.

Private records grow from56 to64 bytes on the measured 64-bit target. Admission, segment
capacity, retained/resident bytes and eviction use actual `sizeof`; policy and byte ceiling
remain unchanged. The extra256-byte preparation-only opcode scratch is included in peak
transient accounting. Original full-width immediates/PCs are retained. Immutable records
remain owned by the invocation's existing segment handle, with the same ARC lifetime.

### Qualification and measured verdict

Keep the composed scalar-result/register-prefix/literal-add model. The aggregate-result
pair prototype regressed Pinky/fill and was rejected. A unified optional-next ABI kept
56-byte records but regressed Pinky9–10% and was rejected. Moving fields alone was within
noise. Separate scalar-only, generic-prefix and identical add-table-without-installation
controls distinguish the final composition from those unsuccessful alternatives; no claim
is made that each component independently wins.

The final isolated comparison covers98 processes (seven guests, both orders, seven
controls). Another96 alternating confirmation processes cover four large guests and
four variants across six rounds. Every process makes13 calls, with three warmups and ten
CPU samples. Paired confirmation median changes versus the actual parent are Pinky-3.28%,
sieve-20.16%, minimal-2.15% and memory fill-11.60%; minimal remains unproven at this scale.
A fresh cumulative70-process comparison uses canonical identical compiler source/cache/
output paths, private clean compiler caches and a byte-identical final image after the
master/parent controls. A preliminary cumulative run overlapped formatting and is retained
separately; the following table uses the clean repeat, with no concurrent formatter/build.

Apple M1 Max, checked ARC/Clang ThinLTO, pristine pinned Nimony
`4724f66c2e01b17810c844f26575b2317995fda2` and PolkaVM
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`. **Reused CPU milliseconds,
forward / reverse process order** (100000 workload limit, Pinky one invocation):

| Guest | Master prepared | Parent #1693 | This implementation | Learning port | PolkaVM interpreted, reused |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 194.915 / 196.766 | 147.767 / 148.278 | 141.998 / 142.790 | 94.581 / 94.251 | 92.126 / 91.869 |
| sieve | 5.853 / 5.862 | 4.412 / 4.405 | 3.507 / 3.513 | 3.394 / 3.395 | 3.487 / 3.503 |
| minimal | 13.514 / 13.531 | 9.212 / 9.223 | 9.010 / 9.018 | 6.221 / 6.209 | 5.982 / 5.977 |
| memset | 6.232 / 6.228 | 4.315 / 4.319 | 3.832 / 3.825 | 3.625 / 3.639 | 3.837 / 3.833 |

Cold CPU milliseconds are single first-call observations, including lazy preparation,
not repeated cold medians:

| Guest | Master cold | Parent cold | This implementation cold | Port cold | PolkaVM cold |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 196.822 / 197.547 | 148.575 / 150.168 | 147.167 / 144.038 | 94.219 / 94.342 | 96.536 / 93.422 |
| sieve | 9.980 / 9.854 | 8.424 / 8.389 | 7.522 / 7.588 | 3.574 / 3.575 | 6.105 / 6.064 |
| minimal | 13.516 / 13.584 | 9.252 / 9.261 | 9.057 / 9.098 | 6.230 / 6.215 | 6.025 / 6.032 |
| memset | 6.353 / 6.357 | 4.447 / 4.465 | 4.028 / 4.089 | 3.650 / 3.647 | 4.000 / 3.988 |

Constructor CPU microseconds cover only creation of the empty bounded prepared owner;
program/initial-memory capture remains outside execution timing. No constructor speed
improvement is established; port/PolkaVM constructors are not measured:

| Guest | Master constructor | Parent constructor | This implementation constructor |
| --- | ---: | ---: | ---: |
| pinky | 5.000 / 4.000 | 6.000 / 5.000 | 5.000 / 4.000 |
| sieve | 4.000 / 5.000 | 5.000 / 4.000 | 4.000 / 4.000 |
| minimal | 14.000 / 13.000 | 14.000 / 12.000 | 11.000 / 13.000 |
| memset | 6.000 / 7.000 | 5.000 / 7.000 | 7.000 / 8.000 |

Sieve and memory fill are within timing noise of PolkaVM interpreted reuse. Pinky and
minimal still cost about1.5 times the learning port. This is neither full lifecycle parity
nor the target of outperforming the reference interpreter. Ragnarök stages each fresh
invocation inside its execution clock; the public Rust reuse adapter restores input
outside that clock. The partial learning port uses predecoded/priced facts and unbounded
retention and does not implement the complete public JAM lifecycle.

All prepared block/operation/hit/eviction counts match the parent for every call in this
comparison. Record growth changes bytes, not churn in these workloads. Final reused cache
observations (resident bytes / peak transient bytes; resident blocks / operations;
cumulative evictions after13 calls):

| Guest | Parent bytes resident / peak | This implementation bytes resident / peak | Blocks / operations | Evictions |
| --- | ---: | ---: | ---: | ---: |
| pinky | 506440 / 523296 | 553728 / 573240 | 792 / 5911 | 751 |
| sieve | 927224 / 944192 | 1033032 / 1052672 | 991 / 13226 | 615 |
| minimal | 134880 / 149216 | 135352 / 151992 | 9 / 59 | 0 |
| memset | 155040 / 169376 | 157960 / 174600 | 63 / 365 | 0 |

These software cache counters are not hardware cache or branch misses. No Linux,
native executed-instruction-count or hardware-event claim is made.

The prepared suite adds all85 register-first ×139 second-opcode combinations (11815),
including aliased descriptors and partial/complete attempt budgets1/2/3 against unchanged
dynamic execution, twice per prepared owner. A focused add/load alias witness covers
192-byte and ordinary cache policies, zero through four attempts, cross-page reads and
the final mapped-page fault. Existing139-opcode, gas/fault/host/reentry,
segment256, byte-pressure, eviction and source-snapshot witnesses remain. Nine native
suites, four independent complete-state references and AddressSanitizer prepared tests
passed; ARC1000 remains balanced. Promoted Make prepared and mixed-reference suites pass.
All timed samples check every register, gas/exit, page byte, permission and retained source
snapshot; tampered gas references are rejected before a successful timing row.

Local samples, source/generated-source identities, native code inspection, rejected
controls, constructor/cold/cache rows and check logs remain under
`build/pvm-port-lab/prepared-register-prefixes`. The qualified runtime source SHA256 is
`14e2991883d89289dfd6c786e97fde584ea0738ca421d545b9b92252246591b1`.
The next bounded investigation is broader literal-prefix coverage or a separately proven
memory-prefix design with exact early-exit attempt accounting; neither is part of this
change. Checked scalar-memory hot/cold separation remains another independent avenue.


## Checked memory-first prefixes, 2026-10-26

Extend bounded prepared pairs to all 30 original checked memory opcode forms. This
independent change starts from #1694 at `3f118b2de0003f2974968387b2d310eb31e937a1`. The Gray Paper,
JAM interpretation, public APIs/defaults, pinned dependencies and memory implementation
remain unchanged. No learning-port implementation ships.

### Exact attempt and exit contract

The existing dispatcher reserves two attempts only when both source cells are retained
and at least two attempts remain. A memory-first prefix calls the original specialized
checked memory handler. On success it transfers to the original second handler, preserving
operand aliasing, all permission/range/COW checks and ordinary PC writes. A first fault,
panic or local failure skips the second handler and tags the original evaluation with a
private high-bit early-return marker. Ordinary complete evaluation words cannot set this
bit: guarded error and exit domains fit their reserved bytes.

Only the closed memory-prefix factory emits this marker, and only after entering the
bounded two-cell path. The existing rare non-continuation branch refunds one reserved
attempt, backs the private operation index up by one and masks the marker before typed
status/exit validation. The prior two-attempt decrement proves the refund cannot overflow;
the two-cell advance proves the index cannot underflow. A first fault therefore publishes
its own causing PC and exact original memory effect. A second fault/host exit retains the
second source site. Local failures publish no state. Default evaluation zero stays
Uninitialized. No marker or mutable frame error side channel reaches the public API.

One remaining attempt, a missing retained successor or byte-pressure segment splitting
uses the original single handler. No first memory result can invoke a host callback.
A successful second host call sees exactly two debited attempts; continuation resumes
from the existing owned location. Private 64-byte records, handler ABI, whole-block pricing,
cache policy/accounting, source snapshots and acyclic ARC ownership remain unchanged.
The continuation path adds no marker decode or frame writes; rare outcomes alone decode
this attempt fact.

### Local qualification and measured verdict

Keep this bounded extension for the useful minimal-workload improvement. Pinky's smaller
change remains cautious evidence; sieve/fill have no established gain. The cumulative
sieve pairs are 1.4–2.7% slower, whereas the isolated and six-round confirmation
comparisons do not establish a useful difference; retain this for minimal, without
claiming a uniform improvement. Six alternating confirmation
pairs, median CPU change versus the immediate parent:

- pinky: -2.01% (range -3.01% to -1.93%).
- sieve: +0.21% (range -0.09% to +1.58%).
- minimal: -4.62% (range -4.86% to -1.74%).
- memset: +0.51% (range -0.70% to +0.68%).

Checked Apple M1 Max ARC/Clang ThinLTO with pristine Nimony
`4724f66c2e01b17810c844f26575b2317995fda2` and PolkaVM
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`. Final isolated comparison has
56 processes, confirmation has 48, and the fresh cumulative comparison has 70. Each makes
13 complete-state calls: three warmups and ten CPU measurements. Master, actual parent
and restored final images use identical canonical compiler source/cache/output paths,
fresh private caches and a byte-identical final image after the controls. Applying
the final pinned formatting also produces byte-identical benchmark images, so all
reported timings cover the final formatted runtime.

Reused CPU milliseconds, **forward / reverse process order** (100000 workload limit,
Pinky one invocation):

| Guest | Master prepared | Parent #1694 | This implementation | Learning port | PolkaVM interpreted, reused |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 195.798 / 197.358 | 142.587 / 141.683 | 140.009 / 138.446 | 95.055 / 94.169 | 92.221 / 92.025 |
| sieve | 5.903 / 6.029 | 3.559 / 3.542 | 3.653 / 3.593 | 3.405 / 3.401 | 3.580 / 3.502 |
| minimal | 13.599 / 13.591 | 9.078 / 9.011 | 8.666 / 8.604 | 6.430 / 6.222 | 5.989 / 6.199 |
| memset | 6.296 / 6.228 | 3.827 / 3.835 | 3.877 / 3.845 | 3.643 / 3.626 | 3.963 / 3.831 |

Cold CPU milliseconds are single first-call observations, including lazy preparation,
not repeated cold medians:

| Guest | Master cold | Parent cold | This implementation cold | Port cold | PolkaVM cold |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 196.757 / 197.494 | 142.879 / 142.793 | 141.269 / 140.145 | 94.549 / 94.532 | 94.960 / 93.747 |
| sieve | 10.187 / 9.858 | 7.605 / 7.576 | 7.786 / 7.776 | 3.565 / 3.566 | 6.209 / 6.134 |
| minimal | 13.552 / 13.592 | 9.092 / 9.361 | 8.938 / 8.639 | 6.262 / 6.240 | 6.063 / 6.026 |
| memset | 6.399 / 6.428 | 4.004 / 3.943 | 3.976 / 3.976 | 3.656 / 3.645 | 4.002 / 3.985 |

Constructor CPU microseconds cover creation of the empty bounded owner only. No constructor
improvement is established; program/memory capture and port/Rust construction are outside
this constructor measurement:

| Guest | Master constructor | Parent constructor | This implementation constructor |
| --- | ---: | ---: | ---: |
| pinky | 4.000 / 5.000 | 5.000 / 5.000 | 5.000 / 5.000 |
| sieve | 4.000 / 5.000 | 8.000 / 4.000 | 4.000 / 5.000 |
| minimal | 15.000 / 12.000 | 13.000 / 12.000 | 12.000 / 11.000 |
| memset | 6.000 / 9.000 | 8.000 / 7.000 | 9.000 / 7.000 |

Every prepared cache observation, including bytes, resident operations/blocks, hits,
preparations, peaks and evictions, exactly matches the parent in all measured calls.
These are software counters, not hardware cache/branch misses. No Linux or executed native
instruction-count claim is made. Rust's reuse adapter resets input outside its clock;
Ragnarök stages each fresh invocation inside its clock. The partial local port uses
predecoded/priced facts and unbounded retention, so neither comparison establishes full
JAM lifecycle parity. Pinky/minimal remain substantially slower than the port/reference;
being faster remains an unmet target.

The prepared suite adds 25020 memory-first/second-opcode/page/permission cases:
30 genuine first forms ×139 genuine second forms ×three mapped/cross-page/end-page
addresses ×two permission settings, with budgets0/1/2/3 and two prepared repetitions.
It retains the 11815 register-first combinations. Independent host witnesses assert
causing PC6, host number13 and the exact first-load value, across successful/faulting
memory, tight192-byte/ordinary caches, zero/insufficient/ample gas, zero through five
attempts and zero/one callback limits. Existing partial-write, host refusal/reentry,
segment-boundary, byte-pressure, eviction and source-snapshot checks remain.

Nine checked native suites, four independent complete-state references, AddressSanitizer
and balanced ARC1000 pass. Promoted Make prepared and mixed-reference suites and format
checks pass. The only originating failure was a test helper's access to mutable global
register inputs; it now receives explicit inputs, with the rejection saved locally.
All timed calls check every register, gas/exit, page byte/permission and original snapshot;
tampered gas references fail before successful timing output.

A separate broader literal-register coverage trial was rejected without a PR: five/eight
families generated 695/1112 direct literal functions, increasing native text from224 KiB
to320/400 KiB. Its72 confirmation processes found no useful broad benefit (eight-family
Pinky-2.30%, sieve-0.86%, minimal+1.05%, fill+0.21%). Static indirect-call elimination
alone was insufficient evidence. Sources/checks/samples remain in
`build/pvm-port-lab/prepared-literal-prefixes`; no rejected source is retained here.

This change's source/generated-source identities, samples/spreads, constructor/cold/cache
rows, equal-image controls and originating verification logs remain in
`build/pvm-port-lab/prepared-memory-prefixes`. Qualified runtime SHA256:
`bd6a1598253e5e97991f6e0c6beeaa390360b4d235d3602ee0f07c200ebf77e6`.
Next investigate redundant prepared facts/layout using the existing exact PC-write
invariant, and profile remaining costs before another execution-model change.


## Bounded dynamic-target working set, 2026-10-26

Increase the invocation-local positive dynamic-target cache from 4 to 256 entries.
The immediate parent is #1695 at `649a7964eaeacd06d7991565f69370d81fde9f3a`;
fresh master remains `ea55b04d60bc8d3113d1dcac3cb537dfe57c7fab`.
This independently implemented policy change affects dynamic, planned and prepared
execution through their existing shared resolver. Public APIs/default selection, JAM
semantics, dependency pins, memory, ordinary PC writes, pricing and 64-byte prepared
records remain unchanged. No translated implementation ships.

### Validated-fact and resource contract

Keep the existing complete ordinal tag, source-bound invocation lifetime and unchanged
validation sequence. Sentinel/alignment precedence remains in `dynamicControl`; a miss
must pass the original jump-table lookup and basic-block membership check before insertion.
A modulo slot alone never authorizes a target. Invalid ordinals, unmarked/interior and
out-of-code destinations remain guest panics and never replace a good fact. Aliased
load-and-jump reads the original base before its required register mutation.

The private cache belongs to exactly one initialized execution cursor's immutable program.
It is neither exported nor retained across invocations, contains no source/machine owner
or back-reference, and never certifies paid gas. The same full-width ordinal/PC fields
are retained. Both fixed arrays use actual length; modulo remains a bounded hash operation,
not ordinal normalization. Bounds/range/assertion checks remain enabled.

There is no new heap allocation or pressure state. The fixed target facts occupy about
6 KiB on this measured 64-bit target, about 6 KiB more than the original four entries.
They are initialized inside each execution clock. Empty prepared-owner constructor and
retained `PreparedInfo` accounting do not include this invocation-local array, just as
before; its fixed additional storage is explicit here.

### Evidence-guided capacity and measured verdict

An independent unclocked copy records the actual lookup sequence while preserving all
reference-state/source checks and prepared-cache observations. Four calls per guest agree.
The four-entry simulation exactly reproduces actual hits. Pinky has 780856 lookups,
776125 actual four-slot misses, and highest ordinal475. Positive-only direct-map
simulation predicts the following software lookup misses:

| Capacity | Pinky misses |
| ---: | ---: |
| 4 | 776125 |
| 16 | 693274 |
| 64 | 312154 |
| 256 | 22388 |
| 512 | 322 |

The 512 prediction follows directly from the 1024 simulation: every observed ordinal
is below512, so both use the same exact slots. These are software target-fact lookup
counts, not hardware cache/branch misses. Minimal already has just3 misses in200000
lookups; sieve100000 has85 misses in97 lookups, falling to71 at16 or more entries;
fill100000 has6 cold lookups. Larger retention should therefore primarily help Pinky.

Keep the fixed256 endpoint. Four-hot-entry plus lazy256/512 spill controls preserve
correctness/ownership but regress sieve by median2.52%/4.03%; they are rejected. This
verdict follows timing, not the simulated miss count alone. Six alternating confirmation
pairs for the retained fixed256 endpoint versus the actual parent:

- pinky: -3.59% (range -4.74% to -2.91%).
- sieve: -0.21% (range -0.92% to +0.04%).
- minimal: -0.13% (range -0.29% to +0.02%).
- memset: +0.26% (range -0.05% to +0.39%).

Only Pinky's prepared gain is established; the other differences remain within noise.
Its cumulative pairs improve by1.56–3.50%, while the six-round confirmation median
is3.59%; the precise gain varies with the process/session.
The final fixed image is byte-identical to its first canonical build after all rejected
controls. Nine final native suites, four final references and AddressSanitizer are rerun
on this exact retained model. No rejected spill type, field, allocation or helper remains.

Checked Apple M1 Max, ARC/Clang ThinLTO; pristine Nimony
`4724f66c2e01b17810c844f26575b2317995fda2`, PolkaVM
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`. Initial84 processes compare
all controls; another96 confirm four endpoints over six alternating rounds. Fresh
cumulative70 processes compare master/actual parent/final/port/Rust. Each makes13
full-state calls: three warmups then ten CPU samples. Source/cache/output compiler paths
are canonical, private caches fresh, and the restored final image remains identical.

Reused CPU milliseconds, **forward / reverse process order** (100000 workload limit,
Pinky one invocation):

| Guest | Master prepared | Parent #1695 | This implementation | Learning port | PolkaVM interpreted, reused |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 196.216 / 194.325 | 139.738 / 138.562 | 134.844 / 136.399 | 95.074 / 94.254 | 92.594 / 92.249 |
| sieve | 5.885 / 5.950 | 3.553 / 3.558 | 3.538 / 3.563 | 3.409 / 3.426 | 3.521 / 3.493 |
| minimal | 13.948 / 13.591 | 8.918 / 8.642 | 8.621 / 8.731 | 6.244 / 6.260 | 6.008 / 6.098 |
| memset | 6.279 / 6.272 | 3.853 / 3.851 | 3.846 / 3.865 | 3.646 / 3.632 | 3.889 / 3.839 |

Cold CPU milliseconds are single first-call observations including lazy preparation,
not repeated cold medians:

| Guest | Master cold | Parent cold | This implementation cold | Port cold | PolkaVM cold |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 197.533 / 196.112 | 140.586 / 166.212 | 136.251 / 134.642 | 94.920 / 94.941 | 93.757 / 94.588 |
| sieve | 9.953 / 9.889 | 7.721 / 7.707 | 7.676 / 7.686 | 3.589 / 3.601 | 6.154 / 6.119 |
| minimal | 14.039 / 13.596 | 8.929 / 8.694 | 8.725 / 8.693 | 6.242 / 6.397 | 6.243 / 6.030 |
| memset | 6.355 / 6.354 | 3.999 / 4.173 | 3.986 / 4.080 | 3.796 / 3.782 | 4.122 / 4.025 |

Empty prepared-owner constructor CPU microseconds; no constructor gain is established:

| Guest | Master constructor | Parent constructor | This implementation constructor |
| --- | ---: | ---: | ---: |
| pinky | 4.000 / 4.000 | 6.000 / 4.000 | 5.000 / 5.000 |
| sieve | 4.000 / 5.000 | 5.000 / 5.000 | 5.000 / 5.000 |
| minimal | 11.000 / 11.000 | 13.000 / 12.000 | 12.000 / 14.000 |
| memset | 6.000 / 6.000 | 7.000 / 9.000 | 10.000 / 9.000 |

Another56 complete-state processes cover the shared resolver's dynamic/planned consumers.
These two-order measurements are coverage, not six-round gain claims:

| Guest | Parent dynamic | Final dynamic | Parent planned | Final planned |
| --- | ---: | ---: | ---: | ---: |
| pinky | 298.002 / 297.473 | 294.307 / 293.886 | 284.599 / 285.360 | 279.334 / 278.846 |
| sieve | 12.152 / 12.137 | 12.136 / 12.145 | 8.466 / 8.460 | 8.458 / 8.470 |
| minimal | 16.392 / 16.401 | 16.425 / 16.298 | 16.037 / 16.017 | 15.970 / 15.987 |
| memset | 8.459 / 8.547 | 8.550 / 8.486 | 8.299 / 8.344 | 8.445 / 8.368 |

Every prepared-cache counter, resident/peak byte observation and eviction count matches
the parent on every measured call. Source snapshots, every register, gas/exit and every
mapped byte/permission pass; tampered gas references fail before successful timing rows.
Profiles are one-second statistical stack samples, not deterministic instruction counts
or hardware events. No Linux or hardware-speed claim is made. Ragnarök stages invocations
inside timing; public Rust resets input outside timing. The local partial port uses
predecoded/priced facts and unbounded retention; complete lifecycle parity is not implied,
and the overall target of being faster remains unmet.

### Boundary and ownership witnesses

Independent programs visit5/17/65/257/513 destinations for three rounds, checking both
plain and aliased load-and-dynamic-jump forms. Visit counts and destination checksums
are asserted independently of either interpreter. A warmed final probe selects the halt
sentinel, zero/odd addresses, an interior marked instruction, an unmarked operand,
out-of-code target or out-of-table ordinal colliding modulo512 with a valid fact.
Partial budgets cover setup and the large working set. The original four-entry endpoint
also passes these independent expectations. Source-owned test framing now accepts explicit
four-byte jump tables while leaving all zero-table fixtures byte-identical.

ARC1000 additionally repeats the collision-heavy program through complete and interrupted
invocations after warming retained prepared arrays. Exact occupied memory remains balanced.
Nine final native suites, four independent references, ASan and promoted Make prepared,
step and mixed-reference suites pass; canonical formatting passes. No APIs, fixture
expectations, source-owned suite metadata or CI jobs change.

Local trace evidence is in `build/pvm-port-lab/dynamic-target-trace`; policy controls,
all samples/spreads, source/generated-source identities, cold/constructor rows, equal-image
controls, final checks and rejected models are in
`build/pvm-port-lab/prepared-dynamic-targets`. Qualified runtime SHA256:
`4064160f8ec7cdfb14ee566dc640ec1225a7ad01167a4fe8383d608f3d04d31d`.
The rejected compact48-byte/56-byte controls remain in `prepared-compact-facts` without
a PR: correctness and maintained-PC witnesses pass, but sieve/fill regress. Remaining
work should follow the accepted engine's profile, including checked scalar-memory hot
paths; smaller records or fewer source checks alone are insufficient evidence.


## Checked scalar-memory cold paths, 2026-10-26

Separate checked scalar-writer miss work from its cached hit paths. Parent is #1696
at `98338fcb00b3634c35f55a2fc4dd1d0c6a6f67c2`; master remains
`ea55b04d60bc8d3113d1dcac3cb537dfe57c7fab`. Only `machine.nim` runtime code
changes. Dependency pins, JAM semantics, public API/defaults, memory representation,
window capacity/replacement, prepared execution, PC writes, pricing, budgets and owner
lifetimes remain unchanged. No translated implementation ships.

### Factoring and ownership contract

The original `loadScalar` and `storeScalar` keep their nil/default-owner checks,
width selection, address normalization, supported-width/range/protected-prefix/exclusive-end
checks and complete single-page cached-window guards. They still use the same checked
page/chunk helpers; stores still prepare every touched private chunk before mutation.
Only the original fallback tails move into private non-inlined `loadWriterMiss` and
`storeWriterMiss` helpers. Small cached workers are marked inline so the optimizer can
see successful outcomes in selected callers.

Callers retain the writer and its immutable base through the callback-free operation.
Private miss parameters borrow genuine non-null writer/source handles after the same
original owner checks; they add neither a new capability nor an ownership transfer.
Span resolution, first-fault/permission precedence, recent-slot updates, page-window
admission, first activation, complete COW preparation, fragment reads/writes and typed
failure construction remain in their original order. Both touched pages are preflighted
before cross-page mutation. Snapshot publication still retires every cached alias.
No checks, assertions, pointer rules or error alternatives are weakened.

### Native and timing evidence

Keep the combined load/store split for the useful minimal and fill improvements.
Load-only and store-only controls isolate the effects; the combined endpoint remains
within the original software-cache accounting and uses identical immutable input memory.
Actual M1 native direct-call sites (`bl`, not executed instruction counts):

| Endpoint | loadScalar sites | storeScalar sites | loadWriterMiss sites | storeWriterMiss sites |
| --- | ---: | ---: | ---: | ---: |
| Parent | 37 | 10 | 0 | 0 |
| Load split | 30 | 10 | 8 | 0 |
| Store split | 37 | 8 | 0 | 6 |
| Combined | 30 | 8 | 8 | 6 |

Some scalar-worker call boundaries disappear; many remain. Static call sites alone
neither establish their dynamic frequency nor a hardware cause for the timing change.
Six alternating confirmation pairs, median CPU change against the immediate parent:

- pinky: -2.77% (range -3.11% to -1.86%).
- sieve: +0.62% (range -0.75% to +4.26%).
- minimal: -9.65% (range -9.74% to -9.58%).
- memset: -5.74% (range -6.03% to -5.47%).

Minimal and fill are supported gains. Pinky's smaller difference is cautious evidence;
sieve is mostly flat with one slower outlier and has no established gain. Do not infer
that fewer source helpers or call sites must improve every workload.

Checked Apple M1 Max, ARC/Clang ThinLTO; pristine Nimony
`4724f66c2e01b17810c844f26575b2317995fda2` and PolkaVM
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`. Initial84 complete-state
processes cover four endpoints plus port/Rust, seven cases and both process orders;
another96 confirm four endpoints across six alternating rounds. Fresh cumulative70
processes compare master/actual parent/final/port/Rust. Every process makes13 calls,
three warmups then ten CPU samples. Canonical source/cache/output compiler paths,
fresh private caches and restored byte-identical final images cover the final source.

Reused CPU milliseconds, **forward / reverse process order** (100000 workload limit,
Pinky one invocation):

| Guest | Master prepared | Parent #1696 | This implementation | Learning port | PolkaVM interpreted, reused |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 195.877 / 195.885 | 133.733 / 133.894 | 130.351 / 130.589 | 94.195 / 94.148 | 91.815 / 91.938 |
| sieve | 5.918 / 5.905 | 3.540 / 3.569 | 3.579 / 3.569 | 3.435 / 3.402 | 3.504 / 3.505 |
| minimal | 13.639 / 13.633 | 8.680 / 8.673 | 7.821 / 7.849 | 6.309 / 6.237 | 6.017 / 5.986 |
| memset | 6.314 / 6.314 | 3.889 / 3.863 | 3.657 / 3.651 | 3.654 / 3.660 | 3.843 / 3.861 |

Cold CPU milliseconds are single first-call observations including lazy preparation,
not repeated cold medians:

| Guest | Master cold | Parent cold | This implementation cold | Port cold | PolkaVM cold |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 203.731 / 195.940 | 135.484 / 135.456 | 131.488 / 131.030 | 94.338 / 94.306 | 96.322 / 93.804 |
| sieve | 9.954 / 9.943 | 7.718 / 7.653 | 7.641 / 7.727 | 3.589 / 3.557 | 6.125 / 6.090 |
| minimal | 13.714 / 13.586 | 8.688 / 8.786 | 7.920 / 7.928 | 6.291 / 6.284 | 6.069 / 6.055 |
| memset | 6.489 / 6.417 | 4.041 / 4.011 | 3.795 / 3.836 | 3.673 / 3.659 | 4.024 / 4.028 |

Empty prepared-owner constructor CPU microseconds; no constructor gain is established:

| Guest | Master constructor | Parent constructor | This implementation constructor |
| --- | ---: | ---: | ---: |
| pinky | 3.000 / 5.000 | 3.000 / 5.000 | 5.000 / 8.000 |
| sieve | 5.000 / 3.000 | 7.000 / 9.000 | 8.000 / 5.000 |
| minimal | 11.000 / 12.000 | 12.000 / 13.000 | 12.000 / 12.000 |
| memset | 7.000 / 6.000 | 7.000 / 9.000 | 8.000 / 7.000 |

Another56 processes cover the changed memory workers through dynamic/planned execution;
these two-order results are not six-round gain claims:

| Guest | Parent dynamic | Final dynamic | Parent planned | Final planned |
| --- | ---: | ---: | ---: | ---: |
| pinky | 291.404 / 292.662 | 287.927 / 290.062 | 279.743 / 282.423 | 276.067 / 277.438 |
| sieve | 12.178 / 12.267 | 12.742 / 12.204 | 8.502 / 8.576 | 8.534 / 8.514 |
| minimal | 16.593 / 16.552 | 16.401 / 16.354 | 16.158 / 16.131 | 15.976 / 15.939 |
| memset | 8.583 / 8.525 | 8.550 / 8.514 | 8.387 / 8.412 | 8.428 / 8.405 |

All prepared-cache counts, resident/peak bytes and evictions match the parent for every
call. All13 timed calls verify every register, gas/exit, mapped byte/permission and
original source snapshot; tampered gas references are rejected before successful timing
rows. These software observations and static native call sites are not hardware branch/
cache misses or executed native instruction counts. No Linux claim is made.
Ragnarök stages invocations inside its clock; Rust restores input outside its execution
clock. The local partial port has predecoded/priced facts and unbounded retention, so
complete lifecycle parity is not established. Pinky/minimal remain slower than that
port and Rust; outperforming the reference overall remains an unmet target.

Existing width/nil/boundary/permission/final-page/COW/epoch/alias checks, full139-opcode
prepared coverage,11815 register pairs,25020 memory pairs, wide dynamic-target sets,
host/gas/budget/reentry and source-snapshot witnesses pass unchanged. Nine native suites,
four independent complete-state references, AddressSanitizer and ARC1000 pass. Promoted
Make scalar-window, prepared and mixed-reference suites plus formatting pass. No new
fixtures, exported APIs, suite metadata or CI jobs are introduced for this refactor.

Samples/spreads, source/generated-source identities, equal-image controls, native text,
constructor/cold/cache rows and verification logs remain under
`build/pvm-port-lab/scalar-cold-paths`. Qualified machine runtime SHA256:
`36283e4b8c353210ba4442cb529e7befc7ee2e6568834080282143ad112be815`.
Next investigate remaining checked-memory working sets/call overhead using separate
unclocked diagnostics; retain the accepted window policy until independent evidence
supports changing it.


## Checked paired segment worker, 2026-10-26

Extract the original paired handler loop into private inline `preparedSegment`; the
caller retains preparation, cache resolution, whole-block charging and exit publication.
Parent #1697 is `e18dc4be28b3e41f3dd1f593a7928dcc9ba65700`; compared master is
`ea55b04d60bc8d3113d1dcac3cb537dfe57c7fab`. No dependency/pin, public API/default,
JAM semantics, memory policy, cache policy, handler ABI or 64-byte operand layout changes.
No translated implementation ships.

The worker borrows the immutable operation sequence from the invocation-retained chunk.
It keeps the exact previous segment/budget tests, two-attempt reservations, one-attempt
fallback and rare memory-first refund. Every ordinary PC write remains. On a boundary it
writes only the final next index and remaining attempts into the invocation frame; the
caller validates the same complete evaluation before constructing observable state. No
user callback or cache replacement runs during this borrowed worker. Fields add 16 bytes
to invocation-local state, not retained cache records. All checks remain enabled.

A non-inlined control regressed; it is not retained. The selected worker has no named
standalone native symbol on M1 after inlining. This is static lowering evidence, not
executed instruction counts, hardware branch/cache data or proof of a CPU cause. Initial
70 processes plus 72 alternating confirmations compared both variants. After selection
and formatting, fresh canonical builds and equal-image controls qualified 56 processes
and 48 six-round confirmations. Median CPU changes against the immediate parent:

- pinky: -1.64% (range -3.20% to -1.22%).
- sieve: -1.30% (range -1.90% to -0.42%).
- minimal: -0.40% (range -1.22% to +0.80%).
- memset: -4.61% (range -6.42% to -4.24%).

Keep the fill gain; the smaller differences elsewhere remain unproven. The repeatable
fill improvement supports this bounded refactor without a general speed claim.

Fresh same-path master/parent/final controls produced another 70 complete-state processes;
restoring final sources reproduced the exact selected image. Every process makes 13 calls:
three warmups and ten CPU samples. Checked ARC/Clang ThinLTO on Apple M1 Max, pristine
Nimony `4724f66c2e01b17810c844f26575b2317995fda2`, PolkaVM
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`. Reused CPU milliseconds, forward / reverse
process order, workload limit 100000 except Pinky one invocation:

| Guest | Master prepared | Parent #1697 | This implementation | Learning port | PolkaVM interpreted |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 196.654 / 197.404 | 130.485 / 130.957 | 129.143 / 129.546 | 94.407 / 94.168 | 92.050 / 92.109 |
| sieve | 5.851 / 5.842 | 3.518 / 3.536 | 3.479 / 3.485 | 3.397 / 3.384 | 3.492 / 3.494 |
| minimal | 13.479 / 13.930 | 7.738 / 7.739 | 7.691 / 7.688 | 6.258 / 6.236 | 5.979 / 5.979 |
| memset | 6.226 / 6.229 | 3.615 / 3.618 | 3.463 / 3.454 | 3.636 / 3.628 | 3.826 / 3.830 |

Cold CPU milliseconds are single first-call observations, not repeated cold medians:

| Guest | Master cold | Parent cold | This implementation cold | Port cold | PolkaVM cold |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 199.464 / 198.004 | 131.672 / 133.847 | 130.680 / 130.835 | 94.233 / 94.358 | 93.494 / 93.486 |
| sieve | 9.881 / 9.847 | 7.625 / 7.596 | 7.706 / 7.493 | 3.576 / 3.552 | 6.095 / 6.095 |
| minimal | 13.645 / 13.723 | 7.857 / 7.801 | 7.735 / 7.744 | 6.259 / 6.249 | 6.042 / 6.025 |
| memset | 6.344 / 6.343 | 3.760 / 3.770 | 3.606 / 3.605 | 3.829 / 3.646 | 4.052 / 4.054 |

Empty prepared-owner constructor CPU microseconds; no constructor gain established:

| Guest | Master | Parent | This implementation |
| --- | ---: | ---: | ---: |
| pinky | 4.000 / 4.000 | 7.000 / 7.000 | 5.000 / 5.000 |
| sieve | 5.000 / 5.000 | 7.000 / 5.000 | 4.000 / 5.000 |
| minimal | 11.000 / 10.000 | 15.000 / 11.000 | 17.000 / 12.000 |
| memset | 6.000 / 6.000 | 7.000 / 6.000 | 6.000 / 6.000 |

Another 56 two-order processes cover the existing dynamic/planned consumers. These are
controls, not six-round gain claims:

| Guest | Parent dynamic | Final dynamic | Parent planned | Final planned |
| --- | ---: | ---: | ---: | ---: |
| pinky | 289.187 / 291.103 | 287.726 / 290.788 | 278.024 / 280.134 | 279.520 / 277.651 |
| sieve | 12.187 / 12.220 | 12.168 / 12.172 | 8.475 / 8.478 | 8.466 / 8.535 |
| minimal | 16.346 / 16.481 | 16.480 / 16.562 | 15.976 / 15.949 | 15.995 / 15.947 |
| memset | 8.535 / 8.470 | 8.507 / 8.486 | 8.456 / 8.324 | 8.428 / 8.438 |

All prepared cache counts, bytes, hits, evictions and occupancy match the parent at every
call. Full registers, gas/exit, mapped bytes, permissions and original source snapshots
pass for all 13 calls; deliberately wrong gas expectations are rejected. Nine selected-code
native suites, four independent references, AddressSanitizer and ARC1000 pass. The new
long-block witness checks all 703 budgets from zero through 702 against the ordinary
interpreter, including every segment/pair boundary; existing 139-opcode, 11815 register-pair,
25020 memory-pair, host/reentry, fault, gas and eviction witnesses remain unchanged.
Promoted Make prepared and mixed-reference suites plus full formatting pass. No fixtures,
registrations or CI jobs change.

Local partial-port predecoded pricing/unbounded retention and Rust input restoration outside
the clock differ from Ragnarök invocation staging. Complete lifecycle parity is not claimed.
These are local M1 measurements, not Linux qualification. Pinky/minimal remain substantially
slower; exceeding the reference overall remains unmet. Native lowering, exact source/image
identities, samples/spreads, cold/constructor/cache rows and rejected noinline evidence are
retained under `build/pvm-port-lab/prepared-segment-worker{,-final}`. Qualified step source
SHA256: `095241ff06387eb4d6f3b2511fd612afe391e91c6c9a19de1cb337c0561c2104`. Next investigate miss-only sparse page resolution without adding
more page-owner probes to the hot scalar path; larger readable-owner windows already failed
local timing qualification.
