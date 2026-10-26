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
