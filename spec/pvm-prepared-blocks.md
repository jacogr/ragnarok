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
