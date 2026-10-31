# Local ARM64 JIT experiment

## Scope and authority

Draft tracking work started from merged interpreter master
`ac4ba21c1486b24ad8ec8967de3208bf7cb470b1` and is reconciled with master
`1a768c26879c14965e4e37bf2ee9ce89bcbb1abd`. GP 0.8.0 and the existing PVM feature contracts
remain authoritative; pinned PolkaVM is a cross-check. This is an optional local experiment,
not a default engine, supported backend, CI requirement or completed compiler.
The October 26 Nimony pin, checked release, ARC and Clang ThinLTO remain unchanged.

## Current retained model

The sections below preserve the chronological experiments; initial limitations in historical
sections do not describe the current implementation.

- Opt in at build time with `pvmArm64Jit`. Production defaults, CLI/backend selection and CI
  selection are unchanged. Native generation is qualified on macOS ARM64 and Linux ARM64;
  Linux x86-64 generation remains future work.
- Lower 53 pure register opcodes and 16 conditional opcodes from sealed source facts. Complete
  pure headers can share native charging/dispatch, and one validated two/three-block register loop
  keeps registers resident across guarded internal edges. Indirect load leaves and read spans
  guard invocation-owned readable regions in native code before a pure arithmetic suffix. Direct
  absolute loads can also share one guarded fragment with a pure suffix and cached conditional.
  A separate [guarded dirty-store self-loop](pvm-arm-dirty-loop.md) admits only the proven
  `198/120/149/149/171` shape after positive branch resolution. Other memory operations,
  hosts and eligibility/resource refusals retain the checked engine.
- Exact-plan prepared owners retain exclusive code/cache ownership across public calls. Native
  bodies borrow only the current thirteen-register file and, for connected execution, a fresh
  bounded scalar gas/budget/count context. Guarded load leaves additionally borrow the current
  frame's three read-region descriptors; compiled code retains no guest-memory/invocation pointer.
  The guarded dirty-store loop also borrows fresh writable descriptors and an already-dirty
  bitmap view for one call, without retaining either pointer. Whole-block gas and source guards
  precede each connected block; partial/paid/error handling,
  fault/exit PCs, source snapshots and ordered host transitions keep their existing workers.
- Immutable arenas remain one MiB with at most 1,024 publications, including one reserved
  connected publication; the separate dirty-store loop uses the ordinary 1,023-fragment
  ceiling so the connected publication retains its reserved slot. The 262,144-node JIT
  coordinate-map bound is a local resource refusal,
  not a whole-program input-size limit. Original checked arena-offset validation stays in calls;
  the publication-sealed alternative was measured and rejected.
- Only connected bodies shorten arithmetic/comparison constants; ordinary fragment layout and
  the fixed five-word branch-return selector retain their measured policy. Native visits use
  exact 64-bit SIMD integer additions, without floating-point arithmetic or callee-saved changes.
- Initial executable-storage refusal is remembered per owner without repeated allocation/map
  growth; a fresh owner can retry. Later capacity refusal preserves existing code. Unsupported
  byte order refuses before native allocation. Full public cold-call clocks include emission and
  publication; the successful regional compilation diagnostic now brackets body emission too.

Both local comparison helpers default to a frozen current HEAD, so a clean checkout gets an
A/A source-and-image control without needing an old draft object. To compare a prior JIT commit,
set `PVM_JIT_BASELINE` to its exact lowercase commit SHA (or use the kernel helper's `--baseline`).
The requested ID must resolve to itself; branch names are not accepted as explicit benchmark heads.
The final session-wide cohort explicitly selects the session's starting commit, not this default.

## First executable increment (historical)


Compile bounded straight-line register operations from genuine sealed handler-stream facts.
Retain block charging, exact source-attempt reservation, budget barriers, source ownership,
checked memory, branches, exceptions, publication and ordered host transitions in the existing
engine. Native fragments receive only the invocation's thirteen-register file for the duration
of a call, never guest addresses, source buffers, callbacks or retained mutable machine state.
Unsupported operations return to the same checked interpreter. Partial source reservations must
use its exact existing barrier path; no native fragment may cross a block header or exit.

Start with simple modular arithmetic/bitwise operations and explicit alias/overflow witnesses.
Executable storage has bounded capacity, explicit ownership and instruction-cache publication.
Only project-generated instruction words may be published. OS refusal leaves execution interpreted.
Apple Silicon requires MAP_JIT and write/execute protection; host policy refusal is a local
availability result. Hardened application entitlement/distribution support is outside this slice.

## Completion evidence required

- Native arithmetic matches the independent register evaluator for aliases and boundary patterns.
- Full CPU/gas/page/permission/source results and ordered host events match the checked engine.
- Exact attempt boundaries, out-of-gas, memory faults, dynamic control and host reentry remain checked.
- Executable storage survives reuse and releases on ownership destruction; admission refusal is tested.
- Record compiler, input and source/image identity. Separate code publication/compilation, cold and
  repeated execution; compare both process orders on one ARM64 host without competing builds.
- Record compiled operation/fragment counts: a passing run with no native execution is not JIT evidence.

The first retained-frame prototype and its local evidence follow below. This does not establish a complete or competitive JIT backend; the draft preserves each subsequent increment.

## Intended platform matrix

The JIT targets Linux x86-64, Linux ARM64 and macOS ARM64. All other CPU/OS combinations are
unsupported for JIT; this does not change interpreter availability. The local experiment now has
native correctness/lifetime evidence on macOS ARM64 and Linux ARM64 in Docker; see the
[Linux qualification](#linux-arm64-platform-qualification). Architecture selection remains separate
from OS allocation/publication policy. Container clocks remain separate from native macOS timing
evidence, and x86-64 code generation remains future work.

## Platform reference

Executable publication follows Apple's [JIT guidance](https://developer.apple.com/documentation/apple-silicon/porting-just-in-time-compilers-to-apple-silicon),
including instruction-cache invalidation. Generated arithmetic remains project-owned and reviewed
against the existing GP register semantics, without translating upstream implementation code.

## First executable prototype

Opt in only with `pvmArm64Jit` through `make bench-pvm-arm64-jit` on Darwin ARM64.
There are no CLI/backend/default changes and no new CI selection or job. The compiler lowers
`and_imm`, `xor_imm`, `or_imm`, `add_imm_64`, `add_64` and `sub_64` into project-generated
AArch64 leaf instructions. Both original operands are read before each write; full immediates
and modulo-2^64 arithmetic preserve saturated coordinates, aliases and overflow patterns.
Every fragment borrows only the exact 104-byte register file; X0–X3 are volatile, and the leaf
changes no stack, link or callee-saved register. It has no guest memory or host callback address.

Cold lazy suffix preparation installs native entry handlers for runs of 2–32 eligible operations.
The ordinary hot loop has no universal JIT probe. Whole-block pricing and source reservation
remain unchanged. Partial reservations call the original checked handlers and observe their
exact temporary barriers. Failed compilation and unsupported instructions retain those handlers.
Native code and original-entry maps are frame-owned in this first slice: stream transfer restores
all original entries and drops executable ownership before a different offset history can arrive.
Public prepared-owner retention of compiled code remains unimplemented; these timings concern
retained frames, not integrated public invocation performance.

The exclusive arena is one MiB with at most 1,024 fragments; source-offset maps admit at most
262,144 stream nodes. Admission/OS refusals preserve interpreted execution. The OS bridge only
allocates, writes, publishes, invokes and retires executable storage. Nim owns instruction
selection and all PVM semantics. Apple MAP_JIT publication toggles thread write protection and
invalidates the instruction cache. Arena payload ownership is move-only under an exclusive
frame-owned reference. These are local experiment bounds, not consensus limits or hardened
application distribution support.

## Local qualification and first timing verdict

Apple M1 Max, pinned October 26 Nimony, ARC, checked release, Clang ThinLTO. Builds and timing
runs are serial. The completed cohort contains 28 timed processes / 364 complete checked calls,
42 positive/assertion/state controls, four fresh compiler-cache builds / two byte-identical pairs,
and 701 sealed source/helper/input/compiler/image identities. Both variants see the same source
attempts and stream-node occupancy for every sample. No hardware counters were collected.

The native witness passes 864 gas/alias/overflow/prepaid/quota/reuse cases against bounded
single-step execution, with 6,912 guest operations actually executed natively. The forced-OS-refusal
variant passes those same cases with zero native operations. Stream transfer retires the old
native cache and executes the restored checked stream; missing-successor input is refused as
`InvalidProgram` during genuine decoding. The first witness incorrectly tried to run that
inadmissible program; its fixture was repaired to assert the exact admission refusal, preserving
the negative case and stream-transfer checks.

Existing 139-opcode/full-state/ARC1000/fused-boundary tests and all 30 checked memory opcodes,
fragmented permission/fault/refund/host-reentry tests pass with the experiment enabled. Other
opcodes remain interpreted, so this is not 139-opcode native coverage. Executable storage passes
1,000 allocation/publication/retirement cycles plus null, length, alignment and exact-capacity
controls. Five parser tests, inventory, formatting and all 453 production modules plus the peer
entry point pass. None of these results establishes complete JAM parity.

CPU ms, forward / reverse. Retained frames; cold includes compilation and publication.

| Case | Interpreter reused | JIT reused | JIT / interpreter | JIT cold | Compilation | Native operations / 13 calls |
|---|---:|---:|---:|---:|---:|---:|
| sieve 1000 | 0.041 / 0.037 | 0.042 / 0.039 | 1.025 / 1.054 | 0.819 / 0.846 | 0.122 / 0.124 | 28509 / 28509 |
| sieve 100000 | 3.317 / 3.248 | 3.522 / 3.425 | 1.062 / 1.055 | 8.207 / 8.164 | 0.580 / 0.600 | 2672891 / 2672891 |
| minimal 1000 | 0.051 / 0.050 | 0.051 / 0.050 | 1.000 / 0.990 | 0.092 / 0.081 | 0.004 / 0.006 | 0 / 0 |
| minimal 100000 | 5.011 / 4.925 | 4.998 / 4.918 | 0.997 / 0.998 | 5.043 / 5.047 | 0.006 / 0.010 | 0 / 0 |
| memset 1000 | 0.042 / 0.038 | 0.044 / 0.040 | 1.060 / 1.053 | 0.256 / 0.242 | 0.075 / 0.059 | 26156 / 26156 |
| memset 100000 | 3.865 / 3.723 | 3.987 / 3.844 | 1.032 / 1.033 | 4.211 / 4.047 | 0.065 / 0.062 | 2600208 / 2600208 |
| pinky 1 | 87.779 / 85.260 | 87.082 / 86.497 | 0.992 / 1.015 | 89.085 / 88.885 | 0.499 / 0.479 | 22807447 / 22807447 |

Native operation counts count guest mutations across all thirteen calls, not executed host
instructions. Cold calls include all lazy stream work plus the complete extra compiler scan,
cache allocation, code generation and publication. The compilation column is that measured
extra phase; source plan/frame construction and reset/publication remain separate receipts in
`results.json`. Reused medians exclude the first three calls, without outlier filtering.

**Verdict: keep as a draft foundation, not a performance improvement.** Minimal is effectively
unchanged; Pinky has mixed small differences; sieve is about 6% slower and larger memory fill
about 3% slower. Two-operation fragments still pay native entry/return and register load/store
costs while most control, charge and memory dispatch stays interpreted. This is a design hypothesis
supported by limited lowering coverage, not a hardware-profile attribution. The rejected initial
integration probed native eligibility on every dispatch and visibly penalized even zero-coverage
minimal; cold-only installation removes that avoidable architecture cost. Its preliminary receipts
remain ignored local investigation data; only the final fresh-cache cohort is qualified above.

Receipts: `build/tests/pvm-arm64-jit/results.json`, `summary.md`,
`independent-verification.json`, qualification/control logs; default-source smoke and parser checks
under `build/pvm-arm64-jit`. Source hashes identify the measured implementation even before its
preserving commit; documentation-only updates do not change those source identities.

## Next bounded work

- Lower longer complete register/control blocks, including charged entry and genuine branch exits,
  before increasing the number of tiny mixed native/interpreted transitions.
- Keep memory access and host boundaries on the current checked paths until independently qualified.
- Measure transition/coverage cost with an isolated straight-line register workload before adding
  memory or whole-application compiler complexity. Full DOOM/public API timing follows broader coverage.
- Retain compiled source-bound code across explicit prepared-owner leases only with exact source
  binding, resource bounds and retirement witnesses; never retain mutable invocation state.
- Add native memory-access lowering, additional platforms and distribution/entitlement policy only
  as separate reviewed increments. No current merge recommendation or default switch.

## Resident register fragments, paired with the initial draft

The next bounded increment expands native arithmetic from six to 44 opcodes, with fragments of
4–64 operations. A leaf keeps the thirteen guest registers in volatile X4–X16; X0 remains the
borrowed register-file base and X1 is immediate scratch. A read-before-write mask loads only
original values the fragment needs, and a dirty mask publishes only modified slots. No SP, LR,
callee-saved register, guest-memory pointer, host callback or frame field enters generated code.
All source coordinates still come from sealed decoder facts. Word arithmetic explicitly sign
extends the low 32-bit result; shifts/rotations retain the GP masked count, including aliases.
Division/remainder and unsupported operations stay interpreted.

Whole-block pricing, exact source reservations/partial barriers, checked memory, host exits,
source snapshots and publication remain unchanged. The OS arena and admission ceilings remain
unchanged. At most 64 operations emit at most six body words each plus thirteen input loads,
thirteen result stores and RET: 411 words, below the existing 1,024-word publisher ceiling.
Source-bound stream transfer still restores original handlers and retires all native ownership.

Native register evaluation passes 1,760 cases over all 44 opcodes, saturated/aliased coordinates
and ten boundary-value seeds, independently checked against the non-code-generating register
evaluator. The matrix caught an incorrect initial assignment of 32-bit multiplication to opcode
196; the corrected opcode is 192 and signed remainder remains interpreted. The full cohort was
rerun after correction. Another 1,536 quota/gas/reuse cases include boundaries around 64 operations,
with 13,824 native mutations; forced executable-storage refusal passes the same matrices with
zero native execution. Stream retirement now explicitly proves four operations executed natively
before transfer; a separate two-operation positive execution proves deliberate short-run fallback.
Full existing opcode/ARC1000 and fragmented-memory/host tests, 1,000 OS storage lifecycles, five
parser checks, formatting and all 453 production modules plus the peer pass.

The initial two-operation admission policy for resident fragments had a separately paired
2.5–3.1% minimal slowdown against the initial draft. A four-operation floor was then measured in
a fresh complete cohort. The two cohorts are retained separately, without dividing times across
runs. The final same-runner table below compares the exact initial draft
`3b8b2e36a60537c57d61a9eec6188c765d0cf92f`, current resident fragments and the plain interpreter.
All three use canonical source/output paths, fresh private compiler caches and one M1 Max host,
with unchanged pinned October 26 Nimony/ARC/checked-release/Clang ThinLTO.

The final cohort verifies all 42 timed processes / 546 complete-state calls, 63 positive/refusal
controls, six fresh builds / three equal-image pairs, 703 sealed input/helper/compiler/image
identities and 1,434 exact captured source/header/driver hashes. Baseline sources are checked
against the immutable commit; current measured sources are checked against the preserving commit.
Every sample has equal source-attempt and stream-node observations across all three modes.
No hardware counters were collected, and no PolkaVM timing was collected in this cohort.

CPU ms, forward / reverse. Retained frames; cold includes compilation and publication.

| Case | Interpreter reused | Previous JIT | Current JIT | Current / previous | Current / interpreter | JIT cold | Compilation | Native operations / 13 calls |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve 1000 | 0.038 / 0.040 | 0.041 / 0.042 | 0.041 / 0.041 | 0.988 / 0.964 | 1.066 / 1.012 | 0.912 / 0.907 | 0.204 / 0.198 | 6019 / 6019 |
| sieve 100000 | 3.247 / 3.277 | 3.447 / 3.465 | 3.239 / 3.272 | 0.940 / 0.944 | 0.998 / 0.998 | 8.018 / 8.219 | 0.676 / 0.705 | 48724 / 48724 |
| minimal 1000 | 0.049 / 0.049 | 0.050 / 0.051 | 0.050 / 0.049 | 1.010 / 0.970 | 1.020 / 1.000 | 0.090 / 0.082 | 0.006 / 0.004 | 0 / 0 |
| minimal 100000 | 4.990 / 4.930 | 4.946 / 4.913 | 4.904 / 4.930 | 0.991 / 1.003 | 0.983 / 1.000 | 5.001 / 5.034 | 0.006 / 0.005 | 0 / 0 |
| memset 1000 | 0.045 / 0.043 | 0.046 / 0.046 | 0.045 / 0.044 | 0.968 / 0.957 | 1.000 / 1.023 | 0.280 / 0.285 | 0.069 / 0.078 | 442 / 442 |
| memset 100000 | 3.747 / 3.704 | 3.854 / 3.873 | 3.676 / 3.689 | 0.954 / 0.952 | 0.981 / 0.996 | 3.876 / 3.998 | 0.069 / 0.075 | 494 / 494 |
| pinky 1 | 85.870 / 85.945 | 87.316 / 87.519 | 79.990 / 80.359 | 0.916 / 0.918 | 0.932 / 0.935 | 83.844 / 85.340 | 0.638 / 0.768 | 95633044 / 95633044 |

### Cold and constructor scopes for the resident-register cohort

CPU milliseconds, forward / reverse. Constructors, reset and immutable publication remain outside
the retained-frame call. Cold calls include all lazy stream and compiler work; compilation is the
complete extra compiler phase, including cache construction, declined runs and OS publication.

| Case | Current plan / frame constructors | Interpreter cold call | Previous JIT cold call | Current JIT cold call | Current cold reset + call + publication |
|---|---:|---:|---:|---:|---:|
| sieve 1000 | 1.549 / 0.153 ; 1.555 / 0.151 | 0.626 ; 0.623 | 0.837 ; 0.823 | 0.912 ; 0.907 | 0.970 ; 0.964 |
| sieve 100000 | 1.516 / 0.161 ; 1.548 / 0.160 | 7.266 ; 7.117 | 8.134 ; 8.007 | 8.018 ; 8.219 | 8.079 ; 8.280 |
| minimal 1000 | 0.010 / 0.021 ; 0.012 / 0.023 | 0.075 ; 0.075 | 0.085 ; 0.086 | 0.090 ; 0.082 | 0.098 ; 0.087 |
| minimal 100000 | 0.010 / 0.018 ; 0.011 / 0.019 | 4.963 ; 4.968 | 4.926 ; 4.961 | 5.001 ; 5.034 | 5.008 ; 5.039 |
| memset 1000 | 0.051 / 1.221 ; 0.049 / 1.194 | 0.163 ; 0.164 | 0.264 ; 0.277 | 0.280 ; 0.285 | 0.508 ; 0.570 |
| memset 100000 | 0.049 / 1.121 ; 0.048 / 1.161 | 3.881 ; 3.849 | 4.088 ; 4.132 | 3.876 ; 3.998 | 4.119 ; 4.368 |
| pinky 1 | 0.478 / 0.203 ; 0.474 / 0.179 | 88.670 ; 87.522 | 90.604 ; 89.724 | 83.844 ; 85.340 | 84.016 ; 85.530 |

**Keep this increment in the draft.** Final Pinky reused CPU improves 8.2–8.4% against the initial
JIT and 6.5–6.8% against the interpreter in both process orders. Sieve regains interpreter parity;
minimal is effectively unchanged; large memory fill has no material interpreter regression and
improves 4.6–4.8% against the initial JIT. Small-input differences of about 1–3 microseconds remain
visible rather than being called wins. No overall public-API or application-speed claim follows
from these retained-frame results.

For Pinky, the previous JIT makes 10,260,848 native entries for 22,807,447 guest mutations across
thirteen calls; current resident fragments make 17,181,853 entries for 95,633,044 mutations.
These are guest coverage/transition observations, not host instruction counts. The data supports
longer resident work per entry as a useful direction; it does not isolate hardware causes or
attribute the total timing delta to one instruction change.

Final receipts replace `build/tests/pvm-arm64-jit/results.json`, `summary.md` and
`independent-verification.json`; initial-draft and two-operation resident cohorts remain under
`build/pvm-arm64-jit/first-prototype` and `resident-minimum-two`. The command now marks outputs
incomplete before work so a failed new invocation cannot leave a stale successful verdict.
Master CI run 40487163010 completed successfully for the merged interpreter; this draft remains
local-only native evidence and has no new JIT CI job or default activation.

The next bounded target is checked native block entry/branch continuation, with explicit source
budget, gas, target and exact-exit witnesses. Guest memory and host boundaries remain on the
current checked paths until separately qualified. Prepared-owner code retention, DOOM/public API
integration, more native opcodes and other CPU/OS targets remain outstanding.


## Conditional continuations and checked entry

This increment compares against the exact accepted resident-register parent
`e6382bc6e5e75ec40edea25d3000df1a4aa5dd6a`. It adds the sixteen GP conditional branches
81–90 and 170–175 to eligible arithmetic leaves. Generated CMP/CSEL returns one of two sealed
scalar stream offsets. It does not embed host addresses or recursively call another block.
Both arms must first have been admitted by the existing branch resolver, witnessed by the exact
original cached handler identity; promotion neither resolves targets nor prices new blocks.

A matching ordinary block header can hand its fully reserved prefix directly to the promoted
leaf. The canonical checked Nim reservation/charge template still performs all gas and source
budget checks, in its original order. Native code does not charge gas. Partial quotas retain
original handlers and temporary barriers, including folded no-op source boundaries. Memo,
error and special header shapes cannot be promoted unless they have already become a genuine
ordinary charge header. All guest memory access and host behavior remain checked interpreter work.

Register publication precedes the scalar return. Immediate comparisons use the full sign-extended
GP value; signed and unsigned conditions remain distinct. Failed replacement publication preserves
the previous valid arithmetic leaf. Transfer restores promoted headers and entries and retires code
ownership. The same arena, map, operation-count and publication ceilings remain in force.

Qualification includes 3,136 direct native branch cases across all sixteen predicates, alias/saturated
register coordinates and signed/unsigned boundary values, using full-width scalar destinations;
2,640 checked engine cases across dynamic, complete and lazy pricing, paid/unpaid blocks, gas,
source quotas and folded no-ops; and 434 host/fault boundary cases with exact identifiers, pages,
remaining attempts and PCs. The host witness distinguishes Psi_1's advanced published PC from the
recursive suspension's attempted instruction PC. A full-arena replacement refusal retains and
executes its last valid publication. Forced storage refusal repeats the engine boundaries with
zero native execution. Existing register, quota, opcode, ARC, memory and host suites remain active.

The final cohort passes 42 timed processes / 546 full-state calls, 63 positive/assertion/state
controls, six fresh private-cache builds / three equal-image pairs, 703 sealed identities and
1,434 captured source/helper/header/driver hashes. The exact parent is read from Git; measured
current source bytes are checked against the preserving commit. Source attempts and stream-node
observations agree for every sample across all three modes. The unchanged default-runtime smoke
passes 453 modules plus peer; the final formatter and seven receipt-parser checks pass.
No hardware counters or PolkaVM timings were collected in this cohort.

Compilation totals include later deferred branch promotion, which can occur after the first cold
sample. Each such cost remains inside its actual call clock; reused medians exclude the first
three calls. Constructors, reset and immutable snapshot publication remain separately measured.
Do not interpret the aggregate compilation diagnostic as work exclusively in the first call.

**Keep this increment in the draft.** Pinky reused CPU improves 2.8–3.0% versus the accepted parent
and 9.2–9.3% versus the interpreter in both orders. Large sieve and minimal remain at parity;
large memory fill is 0.5–1.2% slower than the parent but 0.4–1.9% faster than the interpreter,
below useful timing confidence. Small sieve varies by up to five microseconds and small fill by
up to three microseconds versus the interpreter; retain these costs rather than claiming wins.
Pinky executes 7,384,016 native conditional branches and 2,644,383 checked direct-header entries
across thirteen calls. Subtracting branch counts gives exactly the parent's native arithmetic
coverage on every case/order. This supports the combined control mechanism; it does not isolate
hardware causes or establish public invocation speed.

The final complete cohort follows; its ratios use only this same runner. Earlier cohorts remain
historical evidence. The earlier branch cohort before the additional host/fault witnesses is
preserved at `build/pvm-arm64-jit/control-before-host-boundaries`, and the resident-register parent
cohort at `build/pvm-arm64-jit/resident-accepted`.


CPU ms, forward / reverse. Retained frames; cold includes compilation and publication.

| Case | Interpreter reused | Previous JIT | Current JIT | Current / previous | Current / interpreter | JIT cold | Compilation | Native operations / 13 calls |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve 1000 | 0.041 / 0.040 | 0.040 / 0.038 | 0.045 / 0.040 | 1.125 / 1.026 | 1.111 / 0.988 | 0.907 / 0.891 | 0.213 / 0.188 | 6067 / 6067 |
| sieve 100000 | 3.254 / 3.256 | 3.232 / 3.281 | 3.254 / 3.265 | 1.007 / 0.995 | 1.000 / 1.003 | 8.318 / 8.438 | 0.702 / 0.806 | 48772 / 48772 |
| minimal 1000 | 0.049 / 0.050 | 0.049 / 0.050 | 0.049 / 0.050 | 1.000 / 1.000 | 1.000 / 1.000 | 0.097 / 0.085 | 0.007 / 0.006 | 0 / 0 |
| minimal 100000 | 4.926 / 4.903 | 4.926 / 4.878 | 4.918 / 4.875 | 0.998 / 0.999 | 0.998 / 0.994 | 4.917 / 4.891 | 0.011 / 0.010 | 0 / 0 |
| memset 1000 | 0.043 / 0.043 | 0.045 / 0.046 | 0.044 / 0.046 | 0.989 / 0.989 | 1.035 / 1.070 | 0.270 / 0.263 | 0.090 / 0.080 | 466 / 466 |
| memset 100000 | 3.771 / 3.699 | 3.658 / 3.668 | 3.700 / 3.686 | 1.012 / 1.005 | 0.981 / 0.996 | 3.948 / 3.906 | 0.083 / 0.082 | 518 / 518 |
| pinky 1 | 85.580 / 85.497 | 79.934 / 79.948 | 77.703 / 77.531 | 0.972 / 0.970 | 0.908 / 0.907 | 80.447 / 80.277 | 0.683 / 0.619 | 103017060 / 103017060 |

| Case | Order | Native conditional branches | Checked direct-header entries |
|---|---:|---:|---:|
| sieve 1000 | 0 | 48 | 11 |
| sieve 100000 | 0 | 48 | 11 |
| minimal 1000 | 0 | 0 | 0 |
| minimal 100000 | 0 | 0 | 0 |
| memset 1000 | 0 | 24 | 11 |
| memset 100000 | 0 | 24 | 11 |
| pinky 1 | 0 | 7384016 | 2644383 |
| sieve 1000 | 1 | 48 | 11 |
| sieve 100000 | 1 | 48 | 11 |
| minimal 1000 | 1 | 0 | 0 |
| minimal 100000 | 1 | 0 | 0 |
| memset 1000 | 1 | 24 | 11 |
| memset 100000 | 1 | 24 | 11 |
| pinky 1 | 1 | 7384016 | 2644383 |

### Constructor and cold lifecycle scopes

CPU milliseconds, forward / reverse. Each constructor pair is plan / frame; cold lifecycle is
reset + call + immutable publication. All initialization/publication costs stay visible.

| Case | Plan / frame constructors (F ; R) | Cold lifecycle F / R |
|---|---:|---:|
| sieve 1000 | 1.585 / 0.164 ; 1.606 / 0.177 | 0.966 / 0.949 |
| sieve 100000 | 1.598 / 0.149 ; 1.530 / 0.169 | 8.377 / 8.544 |
| minimal 1000 | 0.013 / 0.025 ; 0.011 / 0.021 | 0.103 / 0.091 |
| minimal 100000 | 0.010 / 0.023 ; 0.011 / 0.020 | 4.926 / 4.903 |
| memset 1000 | 0.051 / 1.228 ; 0.047 / 1.225 | 0.515 / 0.461 |
| memset 100000 | 0.047 / 1.194 ; 0.049 / 1.236 | 4.192 / 4.191 |
| pinky 1 | 0.457 / 0.191 ; 0.460 / 0.186 | 80.626 / 80.516 |

Next priorities are native coverage of hot long-sieve blocks, prepared-owner code lifetime and
DOOM execution with genuine host transitions. Long execution alone does not guarantee benefit:
this sieve cohort executes only 48 native conditional branches across thirteen calls, while
minimal has no qualifying native fragments. Keep small cases as regression checks. Linux ARM64
Docker qualification follows the platform matrix above; no other target is claimed supported yet.


## Prepared-owner and host-memory lifetimes

The next increment moves JIT ownership together with the executable stream across public
`PreparedProgram` leases. It retains only code, exact immutable plan identity, scalar offsets,
original checked fallback handlers and diagnostic counters. Every invocation still creates fresh
registers, memory regions, attempt budgets and host state. A different plan is refused before the
stream is consumed. JIT-enabled frames and streams explicitly reject compiler-generated copies;
positive move controls and intended lowering diagnostics are retained by the local runner.

A same-plan whole-memory replacement now moves the native cache with its handlers. The first
real-application cohort exposed the missing move: retained DOOM initialization passed its first
sample, then stopped on a checked invariant when the next replacement left native handlers without
their cache. The failed cohort is retained under
`build/pvm-arm64-jit/retention/failed-first-application` and supplies no timing verdict. A focused
witness now covers whole-memory replacement and genuine host fallback into an independently owned
mapping, source immutability, fresh CPU state and continued native execution. No guest-memory or
host pointer enters generated code, so memory replacement requires no new machine-code operands.

`make bench-pvm-arm64-applications` is a local-only comparison of public interpreted execution,
the exact parent JIT, current public JIT, retained-frame JIT and pinned PolkaVM interpreted.
It includes normal and ten-million-element sieve, Pinky, minimal, memory fill and DOOM init/gameplay.
All cases retain complete CPU/gas/register/memory/permission/source checks; DOOM also checks every
ordered output event. Constructors, cold calls, reused calls and core reset/publication are separate.
Reference DOOM restoration/call/teardown records are validated separately from raw call ratios.
No CI selection, default backend, dependency revision or compiler upgrade changes in this increment.

### Qualified local application evidence

Both cohorts are independently verified at the preserving commit: native kernels have 42 timed
processes / 546 full-state calls, 63 controls, six fresh builds / three equal-image pairs, 705
sealed identities and 1,434 source hashes; applications have 70 timed processes / 910 full-state
calls, 115 controls, sixteen fresh builds / eight equal-image pairs, 709 sealed identities and
1,916 source hashes. Application inputs include a freshly reference-produced ten-million sieve.
All complete DOOM admission checks, ordered host events and exact expected CPU/memory states pass.
The final native witness includes explicit same-plan whole-memory replacement and independent
host mapping fallback. Eleven parser tests, formatting and default smoke across 453 modules plus
peer pass. Lowering refuses both frame and stream duplication with the intended diagnostic, and
both explicit move controls execute successfully. No hardware counters were collected.

**Keep the lifetime increment.** It enables actual public prepared-owner code reuse and fixes a
real host/memory replacement defect. Pinky public reused CPU improves about 7–8% against the
previous public JIT and interpreted API. Long sieve changes versus our interpreter are small;
there is no claim that its main loops are compiled. DOOM initialization has a small improvement.
The original gameplay reverse order was slower; three further paired repetitions of the same
sealed images do not reproduce that slowdown and show essentially no parent delta. The draft
retains that original result rather than replacing it with the more favorable repeat.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.536 / 3.490 | 3.461 / 3.449 | 3.523 / 3.438 | 3.225 / 3.236 | 5.945 / 6.064 | 0.996 / 0.985 | 0.593 / 0.567 |
| minimal 100000 | 4.994 / 4.957 | 5.035 / 4.942 | 4.848 / 4.933 | 5.079 / 4.893 | 6.300 / 6.056 | 0.971 / 0.995 | 0.770 / 0.814 |
| memset 100000 | 4.550 / 4.410 | 4.473 / 4.418 | 4.428 / 4.435 | 3.723 / 3.665 | 3.995 / 3.933 | 0.973 / 1.006 | 1.109 / 1.128 |
| pinky 1 | 85.807 / 85.177 | 85.377 / 85.212 | 79.094 / 78.049 | 78.632 / 77.234 | 94.459 / 94.421 | 0.922 / 0.916 | 0.837 / 0.827 |
| sieve 10000000 | 338.943 / 340.343 | 335.210 / 335.397 | 334.151 / 332.057 | 336.342 / 333.303 | 367.098 / 367.127 | 0.986 / 0.976 | 0.910 / 0.904 |
| init 0 | 327.652 / 323.995 | 324.045 / 319.780 | 319.573 / 318.625 | 323.391 / 317.921 | 677.080 / 677.554 | 0.975 / 0.983 | 0.472 / 0.470 |
| tick 0 | 41.356 / 40.291 | 39.875 / 40.380 | 39.572 / 42.358 | 37.944 / 35.980 | 44.508 / 44.291 | 0.957 / 1.051 | 0.889 / 0.956 |

Each row is a distinct scope: public calls include invocation construction and immutable publication;
core reset/publication are outside its call; reference call time excludes restoration/teardown.
The ratios above are raw call ratios, not equivalent end-to-end lifecycle ratios. The reference
module constructor is not timed here. Current public constructor and first cold call, plus the
separate retained-core cold lifecycle, follow in milliseconds, forward / reverse.

| Case | Public prepared constructor | Public cold call | Core plan / frame (F ; R) | Core cold reset + call + publication |
|---|---:|---:|---:|---:|
| sieve 100000 | 1.688 / 1.626 | 8.682 / 8.631 | 1.515 / 0.156 ; 1.596 / 0.188 | 8.144 / 8.140 |
| minimal 100000 | 0.011 / 0.014 | 5.178 / 4.969 | 0.010 / 0.019 ; 0.009 / 0.020 | 5.161 / 4.913 |
| memset 100000 | 0.052 / 0.052 | 5.921 / 5.843 | 0.048 / 1.243 ; 0.053 / 1.223 | 4.212 / 4.057 |
| pinky 1 | 0.459 / 0.461 | 81.302 / 80.854 | 0.461 / 0.186 ; 0.478 / 0.191 | 80.380 / 80.409 |
| sieve 10000000 | 1.617 / 1.632 | 340.210 / 337.581 | 1.537 / 0.146 ; 1.573 / 0.179 | 341.918 / 338.248 |
| init 0 | 7.615 / 7.870 | 343.162 / 334.978 | 7.853 / 5.813 ; 7.568 / 6.446 | 342.894 / 341.807 |
| tick 0 | 7.881 / 7.835 | 49.436 / 50.903 | 7.894 / 6.271 ; 7.825 / 6.624 | 48.630 / 48.142 |

Reference DOOM reused lifecycle medians, milliseconds, forward / reverse:

| Phase | Restoration | Call | Teardown | Total |
|---|---:|---:|---:|---:|
| init | 2.103 / 2.095 | 677.080 / 677.554 | 0.006 / 0.006 | 679.245 / 679.641 |
| tick | 2.095 / 2.099 | 44.508 / 44.291 | 0.005 / 0.005 | 46.566 / 46.367 |

The separate gameplay repeat uses the same sealed images and inputs: thirty processes / 390 checked
calls, three complete forward/reverse pairs. Public JIT reused medians range 39.444–39.945 ms,
public interpreter 40.180–40.760 ms, parent JIT 39.603–39.912 ms and reference call 44.090–44.667 ms.
Current/interpreter ranges 0.970–0.986; current/parent 0.994–1.001; current/reference 0.883–0.899.
These are separate paired evidence, not replacements mixed into the original cohort.

### Long-sieve coverage diagnosis

An ignored, separately compiled interpreter source copy counts actual block entries on the same
complete ten-million fixture. All state checks pass; every instrumented clock is discarded.
The busiest seven-operation block at source PC 156868 executes five million times and contains
opcodes `[151,200,130,133,208,132,40]`: indirect 64-bit load opcode 130 splits native arithmetic.
Another block at 156840 executes 9,999,999 times with `[149,200,170]`; 156849 executes 9,999,999
with `[132,81]`; 156855 and 156861 each execute five million times with `[152,174]`. These short
arithmetic/conditional blocks fall below the four-operation admission floor. This identifies
checked memory lowering and short-block control execution as bounded future targets; it does
not justify globally lowering the floor without measurements. Source copy, trace and decoded
block observations remain under `build/pvm-arm64-jit/hot-blocks`. Native public counters and full
constructor/cold samples remain in the application receipts. No native-memory or full-JIT claim
is made by this lifetime increment.


## Linux ARM64 platform qualification

The optional experiment now runs on macOS ARM64 and Linux ARM64. This adds the official
`linux_arm64` archive and matching formatter for the **same** October 26 Nimony commit; neither
compiler nor formatter revisions change. GitHub release asset digests are pinned in
`spec/toolchain.json` and the ordinary installer verifies hashes, archive metadata and banners.
The production Docker target remains independently qualified on Linux x86-64; no production
backend, default, CLI or CI platform selection changes here. Native x86-64 code generation is
still planned; other CPU/OS combinations remain unsupported for JIT.

Linux uses a bounded memfd backing with separate shared RW and RX aliases. The descriptor closes
after mapping, and every partial admission path closes/unmaps its admitted resources before
returning refusal. Publication copies only into the writable alias, then uses the compiler's
instruction-cache publication primitive for the written and executable aliases before exposing
the scalar offset. Previously published bytes never change. macOS retains its existing MAP_JIT
and thread write-protection path. The OS boundary remains narrow; GP semantics stay in Nim.
See the [glibc memory-mapping API](https://sourceware.org/glibc/manual/latest/html_node/Memory_002dmapped-I_002fO.html)
and [instruction-cache builtin contract](https://gcc.gnu.org/onlinedocs/gcc/Other-Builtins.html).

`make check-pvm-arm64-jit-docker` stages only explicit source and sealed reference-produced fixture
bytes, provisions the same pinned ARM64 tools in a private image, then runs with networking disabled
and no host mounts. It preserves the created container's logs/results and removes only that
container. `make check-pvm-arm64-jit-linux` is its native inner entry point. The native gates are
shared directly with the macOS runner: full register/branch matrices, source budgets/gas, opcode
and ARC suites, host/memory boundaries, storage refusal and explicit owner move/copy lowering.
Linux additionally checks individual mapping permissions, both failed mapping admission paths,
unchanged descriptor counts over 1,000 lifetimes, appended publication and retained old code.

The completed Linux run uses native `aarch64`, Linux 5.15.49-linuxkit/glibc 2.39,
compiler SHA-256 `5eb5f0d8ef1c1fd388845fa1139a54475cb889f40056b37a7b63f045812239ff`, and image
`sha256:ec7be80d8f8746f2cecd56e8813845f14609e87e95760de698277100c0406942`.
Independent verification confirms nine shared native gates, fourteen public processes / **182**
complete-state calls, **32** assertion/state/event refusal controls, four freshly built public
images and **2,863** sealed source/configuration/fixture files unchanged within the run. The
fixture source is the preceding qualified application cohort; Linux performs its own complete
CPU/gas/register/page/permission/source and ordered-host-event checks against those expected bytes.
No reference executable or host compiler/cache is reused inside the container.

Native coverage agrees with the macOS cohort, including Pinky 103,017,060 compiled guest operations,
DOOM initialization 41,177,248 and gameplay 16,013,017 across thirteen calls each. These are guest
coverage counters, not host instructions or hardware performance counters. All container clocks
are diagnostic only: there is **no Linux-versus-macOS timing ratio** and no claimed Linux speed gain.
The same nine native gates pass again on macOS with the current OS header; host selection, eleven
parser tests and formatting checks pass. Existing production Nim sources are unchanged by this
platform increment, so the preceding identical-source default smoke remains applicable.

The first two Docker attempts retained useful staging failures: missing required unit output
contracts, then an omitted native header. Both were fixed by staging the original required files;
no check was weakened. Their logs remain under `build/pvm-arm64-jit/linux/failed-*`. Final receipts,
sealed context, image metadata and independent verification remain under
`build/pvm-arm64-jit/linux/`. Source-base commit is recorded separately from the full working-source
seals; production/runtime/helper/toolchain bytes are checked against the preserving commit.
Documentation-only updates follow qualification and do not alter the measured implementation.

Linux ARM64 now has the same local correctness and lifetime baseline as macOS for this native
slice. Further speed work remains paused for the platform qualification; the next measured design
questions are short-block entry/exit costs and checked-memory coverage identified by the sieve
trace. No fully native PVM, production readiness or merge recommendation follows from these checks.


## Short conditional-block admission trial

The next isolated trial admits one to three supported arithmetic operations only when their
immediate successor is a genuine conditional branch. Other short leaves retain the four-operation
floor. Native branch promotion still requires both cached positive scalar arms, and header fusion
still performs the original complete reservation. Pricing, partial-budget fallback, source PCs,
checked memory, host handling, native ABI, code ownership and the 1,024-publication/one-MiB limits
are unchanged. The native slice remains explicit and experimental; no production default changes.

The exact accepted parent is `8fb019b726e53e9e0622d56ee85a54909793c1d8`. Current working-source
hashes are sealed in the receipts and checked against the later preserving commit. The expanded
folded/unfolded one/two/three/four-operation witness passes 10,560 gas, attempt-budget and pricing
cases, plus the existing opcode, host/memory, storage-refusal and move/copy ownership gates.

### Same-cohort macOS ARM64 public results

Apple M1 Max, pinned October 26 Nimony, checked release/ARC/Clang ThinLTO. CPU milliseconds,
forward / reverse process orders; reused medians use samples 3–12 of thirteen complete checked calls.
Public calls include fresh invocation memory, genuine hosts and immutable publication. Reference
call clocks exclude restoration/teardown, whose separate DOOM lifecycle receipts are also checked.
Retained-core reset/publication remains a separate scope and is not used for public ratios.

| Case | Public interpreter | Accepted public JIT | Current public JIT | PolkaVM interpreted call | Current / parent | Current / reference |
|---|---:|---:|---:|---:|---:|---:|
| pinky 1 | 84.665 / 85.335 | 76.323 / 77.001 | 75.962 / 76.228 | 93.291 / 93.989 | 0.995 / 0.990 | 0.814 / 0.811 |
| sieve 100000 | 3.446 / 3.417 | 3.417 / 3.375 | 2.794 / 2.771 | 5.930 / 5.891 | 0.818 / 0.821 | 0.471 / 0.470 |
| sieve 10000000 | 337.414 / 338.793 | 334.430 / 334.613 | 279.183 / 279.072 | 368.687 / 369.264 | 0.835 / 0.834 | 0.757 / 0.756 |
| minimal 100000 | 4.918 / 4.875 | 4.935 / 4.872 | 4.871 / 4.867 | 5.998 / 5.994 | 0.987 / 0.999 | 0.812 / 0.812 |
| memset 100000 | 4.335 / 4.320 | 4.311 / 4.314 | 3.453 / 3.439 | 3.922 / 3.926 | 0.801 / 0.797 | 0.880 / 0.876 |
| init 0 | 320.352 / 322.976 | 318.647 / 315.043 | 316.185 / 315.291 | 676.184 / 671.608 | 0.992 / 1.001 | 0.468 / 0.469 |
| tick 0 | 39.821 / 40.222 | 39.654 / 39.475 | 36.864 / 36.788 | 44.048 / 44.215 | 0.930 / 0.932 | 0.837 / 0.832 |

### Constructor, cold and coverage costs

Prepared-owner constructor and native compilation costs remain separate; compilation/publication
also remains inside each cold call. Coverage below counts compiled guest operations across thirteen
calls, not host instructions or hardware counters. No hardware counters were collected.

| Case | Current owner ctor ms | Current cold ms | Parent cold ms | Current compile ms | Publications | Native guest operations / 13 calls |
|---|---:|---:|---:|---:|---:|---:|
| pinky 1 | 0.454 / 0.462 | 79.058 / 78.540 | 79.456 / 79.753 | 0.790 / 0.749 | 514 | 137037306 |
| sieve 100000 | 1.628 / 1.595 | 7.691 / 7.666 | 8.285 / 8.226 | 0.732 / 0.719 | 253 | 9206651 |
| sieve 10000000 | 1.696 / 1.622 | 284.141 / 284.230 | 338.977 / 339.568 | 0.837 / 0.833 | 253 | 924980744 |
| minimal 100000 | 0.010 / 0.010 | 4.929 / 4.924 | 4.988 / 4.917 | 0.016 / 0.014 | 2 | 25 |
| memset 100000 | 0.052 / 0.051 | 5.019 / 4.771 | 5.673 / 5.615 | 0.096 / 0.077 | 47 | 9100943 |
| init 0 | 7.739 / 7.568 | 337.578 / 335.005 | 334.083 / 334.060 | 3.621 / 3.767 | 1024 | 54065702 |
| tick 0 | 7.568 / 7.812 | 45.689 / 46.486 | 48.494 / 49.546 | 1.147 / 1.178 | 720 | 72738125 |

### Verdict and automatic admission direction

Keep this isolated trial: public sieve improves roughly 17–18%, long sieve 16–17%, memory fill
about 20% and gameplay about 7% against the accepted native parent, consistently in both orders.
Pinky, minimal and reused initialization remain close to parent; no useful gains are claimed there.
DOOM initialization reaches the unchanged 1,024-publication cap and safely falls back for later
candidates. Its cold call is about 0.3–1.1% slower than parent; that cost is retained rather than
being hidden by reused medians. Gameplay uses 720 publications. No larger cache was introduced.

Independent verification checks all 42 kernel processes / 546 calls / 63 controls / six builds
(three equal-image pairs), plus 70 application processes / 910 calls / 115 controls / sixteen builds
(eight equal-image pairs). Exact baseline source hashes and all 706 kernel / 710 application
input, source, helper, compiler and image seals match. Eleven parser tests and pinned formatting pass.
Receipts are under `build/tests/pvm-arm64-jit` and `build/tests/pvm-arm64-applications`;
prior cohorts and the independent verifier are retained under
`build/pvm-arm64-jit/short-conditional`. Linux qualification of this increment is recorded separately.

Admission remains opportunistic per block, with the existing bounded code cache and checked
interpreter fallback. The qualified workloads give no reason to impose a whole-program size cutoff;
large repeatedly executed applications remain an important target. Further admission decisions should
follow measured reuse and compilation costs. No production default changes in this draft.


The retained trial also passes a fresh isolated Linux ARM64 Docker qualification: nine shared
native gates (including the expanded 10,560-case boundary witness), four public image builds,
14 public processes / 182 checked calls, 32 assertion/state/host-event refusals and 2,863 sealed
source/configuration/fixture files. Independent protocol and source/image checks pass. Linux
clocks remain diagnostic only; the timing table above is macOS-only. Receipts are under
`build/pvm-arm64-jit/linux`; the preceding platform cohort is preserved under
`build/pvm-arm64-jit/short-conditional/prior-linux`.


## Compact constant materialization: rejected

Two isolated constant-emission variants were qualified against accepted runtime
`4af05970f9309e38f3cb9e910b0b2cc7fe014686`. The combined variant chooses MOVZ/MOVN plus only
differing MOVK halfwords and uses that helper for scalar conditional destinations. The second keeps
only arithmetic constant shortening and restores the accepted branch-destination words.
Neither variant changes admission, reservation, budgets, memory/host semantics, native ABI or cache caps.

Combined measured/preserving head: `d1a1bc9f21199046c0a8c5f8cc5e0d998b502dca`.
Arithmetic-only measured/preserving head: `2ab9f62f88cef97f2ff09ac4ee0608c13703c203`.
Both variants are rejected; the final runtime is restored byte-for-byte to the accepted parent.
Their commits and sealed local records preserve the measured implementation rather than claiming
a timing result for the later restoration commit.

### Paired retained-core CPU results

Apple M1 Max, unchanged pinned checked release/ARC/Clang ThinLTO. CPU ms, forward / reverse.
Each row compares its own same-runner parent and variant; the two cohorts are not directly paired.

| Variant | Case | Accepted parent | Trial | Trial / parent |
|---|---|---:|---:|---:|
| Combined | sieve 100000 | 2.763 / 2.756 | 3.263 / 3.271 | 1.181 / 1.187 |
| Combined | minimal 100000 | 4.897 / 4.891 | 4.920 / 4.904 | 1.005 / 1.003 |
| Combined | memset 100000 | 2.773 / 2.747 | 2.797 / 2.695 | 1.009 / 0.981 |
| Combined | pinky 1 | 76.306 / 76.181 | 76.259 / 75.844 | 0.999 / 0.996 |
| Arithmetic only | sieve 100000 | 2.745 / 2.748 | 3.168 / 3.179 | 1.154 / 1.157 |
| Arithmetic only | minimal 100000 | 4.831 / 4.842 | 4.848 / 4.839 | 1.004 / 0.999 |
| Arithmetic only | memset 100000 | 2.743 / 2.743 | 2.795 / 2.708 | 1.019 / 0.987 |
| Arithmetic only | pinky 1 | 75.927 / 75.916 | 75.412 / 75.377 | 0.993 / 0.993 |

### Combined variant public application results

CPU ms, forward / reverse, reused public medians. Fresh invocation memory and immutable
publication remain inside our calls; reference raw calls exclude restoration/teardown, whose DOOM
lifecycle receipts are also checked. Retained-core results above are a different scope.

| Case | Accepted public JIT | Trial public JIT | PolkaVM interpreted call | Trial / parent |
|---|---:|---:|---:|---:|
| pinky 1 | 76.642 / 76.431 | 76.066 / 76.123 | 95.468 / 94.248 | 0.992 / 0.996 |
| sieve 100000 | 2.842 / 2.820 | 2.890 / 2.888 | 5.961 / 6.075 | 1.017 / 1.024 |
| sieve 10000000 | 278.670 / 275.558 | 290.340 / 281.818 | 366.714 / 368.882 | 1.042 / 1.023 |
| minimal 100000 | 4.928 / 4.897 | 4.958 / 4.921 | 6.049 / 6.038 | 1.006 / 1.005 |
| memset 100000 | 3.461 / 3.450 | 3.424 / 3.421 | 3.947 / 3.945 | 0.989 / 0.992 |
| init 0 | 318.478 / 314.299 | 323.175 / 314.870 | 671.534 / 671.957 | 1.015 / 1.002 |
| tick 0 | 37.188 / 37.034 | 36.717 / 36.703 | 44.238 / 44.287 | 0.987 / 0.991 |

### Verdict and retained checks

Combined native emitted bytes fell from 22,228 to 14,220 on sieve and 44,092 to 26,348 on Pinky,
with identical fragment counts, native calls and compiled guest operation counts. This smaller
code does not establish a speed benefit: retained sieve regressed about 18%, and public long sieve
about 2–4%. Other public deltas are too small to justify that regression. Restoring the accepted
branch words still leaves arithmetic-only retained sieve about 15–16% slower, with no useful
other kernel gain. The latter therefore stops at the qualified kernel gate; no public or Linux
performance result is claimed for that variant. No hardware counters were collected, so no
particular CPU/cache/predictor cause is inferred from code size or instruction forms.

Combined qualification: nine native gates; 42 kernel processes / 546 calls / 63 controls / six
fresh builds (three equal-image pairs); 70 public/core/reference processes / 910 calls / 115 controls
/ sixteen fresh builds (eight equal-image pairs). Arithmetic-only qualification: the same nine
gates and 42 kernel processes / 546 calls / 63 controls / six fresh builds. Independent re-parsing,
source/input/compiler/image seals and exact parent source checks pass for both measured cohorts.
Tracked measured sources match their preserving commits. Receipts and rejection records remain
under `build/pvm-arm64-jit/constants/full-variant-*` and `arithmetic-variant-kernels`.

The first added constant fixture was 26 bytes wide and failed program admission before native
emission. Correcting it to the decoder's existing 25-byte maximum fixes the fixture; the failed
input/log is retained under `constants/first-failure`. No decoder check was changed.
The useful 1,209-case witness is retained: every guest destination, zero/all-ones/high-halfword
constants and all four-halfword mixtures of zero/ones/nontrivial values execute against literal
expected values, with all unrelated registers preserved. Compact-word-count expectations are
removed with the rejected emitter; emitted-code extent and exact register-value checks remain.
Both native and explicit executable-storage refusal paths are rerun against the restored runtime.
Previous macOS/Linux runtime qualification applies to that identical accepted implementation.

Full native compile mode and execution selection are tracked in
[#1733](https://github.com/jacogr/ragnarok/issues/1733): Linux x86-64 and Linux/macOS ARM64,
eventual qualified default JIT with explicit opt-out, independently selectable full compile mode,
and separate compilation/cold/reused/reference-compiled measurements. No new default is enabled.


## Checked head-load fusion: rejected

An isolated opcode-130 head-load experiment was measured against accepted head
`95841b75cf69d4179b38161b7057407f648069cb`. An ignored diagnostic source copy counted
memory visits on all seven workloads; its clocks were discarded. All accesses used existing
contiguous-region fast checks, with zero slow load/store fallback hits. Long sieve performed
15,475,522 memory accesses, including 9,132,792 unsigned indirect 64-bit loads; one source site
accounted for 5,000,000 loads followed by three register operations and a static jump. These
counts identify a candidate boundary; no CPU sampling or hardware-counter cause is claimed.

The trial preserved address/protected-prefix/extent/permission checks in Nim and borrowed one
fully admitted word for a native head load plus at least three register operations. It cached no
guest pointer. Partial whole-block reservations, fragmented/refused extents and conditional-ending
shapes retained canonical handlers. Existing pricing, code-cache caps, memory ownership and
source/host semantics were unchanged. The trial is rejected: its retained-core improvement did
not establish a useful public-call improvement across the application cohort.

### Same-cohort public CPU medians

Apple M1 Max, pinned checked release/ARC/Clang ThinLTO. CPU ms, forward / reverse. Our public
calls include fresh invocation memory and immutable result publication. Reference raw calls exclude
restoration/teardown; separate DOOM lifecycle records were checked.

| Case | Accepted JIT | Trial JIT | PolkaVM interpreted | Trial / accepted |
|---|---:|---:|---:|---:|
| sieve 100000 | 2.853 / 2.816 | 2.814 / 2.794 | 5.981 / 5.960 | 0.986 / 0.992 |
| sieve 10000000 | 272.537 / 272.798 | 273.620 / 276.108 | 377.584 / 369.159 | 1.004 / 1.012 |
| minimal 100000 | 4.936 / 4.906 | 4.938 / 4.910 | 6.038 / 6.040 | 1.000 / 1.001 |
| memset 100000 | 3.591 / 3.452 | 3.504 / 3.456 | 3.945 / 3.940 | 0.976 / 1.001 |
| pinky 1 | 78.733 / 76.373 | 78.918 / 76.509 | 96.374 / 94.065 | 1.002 / 1.002 |
| init 0 | 323.207 / 324.560 | 320.041 / 322.659 | 671.381 / 671.688 | 0.990 / 0.994 |
| tick 0 | 37.075 / 37.143 | 36.513 / 37.373 | 44.209 / 45.321 | 0.985 / 1.006 |

The separate paired retained-frame kernel cohort improves sieve100k from 2.767 / 2.751 to
2.524 / 2.486 ms (about 9–10%). Public sieve100k improves only 0.8–1.3%, while long sieve
is 0.4–1.2% slower. Other public changes do not show a consistent useful gain in both orders.
These scopes are not interchangeable; the runtime experiment is restored rather than retained
on the strength of a core-only result. No Linux qualification is claimed for this rejected trial.

Qualification passed nine shared native gates, including 4,800 added load/address/permission/
pricing/budget cases and explicit host remap/unmap replay. The kernel cohort has 42 processes /
546 calls / 63 controls / six fresh builds (three equal-image pairs); the public/core/reference
cohort has 70 processes / 910 calls / 115 controls / sixteen fresh builds (eight equal-image pairs).
Independent re-parsing verified every call, control, source/input/compiler/image seal and exact
accepted-parent source identity (706 kernel and 710 application seals). Records remain under
`build/pvm-arm64-jit/head-load` and the corresponding sealed application/kernel receipts.

The host witness initially expected native work under a partial whole-block reservation. The
trace confirmed correct interpreted fallback; the witness now checks that boundary and a separate
full-reservation replay before unmapping. A compiler alias rejection was fixed by hoisting scalar
gas/register values before a mutable resume call. No runtime check was weakened. The next
question is why retained-frame gains fail to survive public execution, before expanding memory
lowering further.

Measured/preserving trial commit: `c00821923bdf1ccb62dcfd7e45f1a0e031cfa942`. The subsequent restoration keeps the accepted
runtime byte-identical to `95841b75`; the useful 4,800 memory boundary cases and host-map witness
remain, with native-coverage expectations removed for the rejected shape.

Constructor CPU and first-call CPU are separate from the reused table. CPU ms, forward / reverse.
The first call includes lazy stream/native preparation and executable publication.

| Case | Accepted constructor | Trial constructor | Accepted cold call | Trial cold call |
|---|---:|---:|---:|---:|
| sieve 100000 | 1.627 / 1.597 | 1.676 / 1.611 | 7.815 / 7.782 | 8.191 / 7.815 |
| sieve 10000000 | 1.623 / 1.565 | 1.619 / 1.629 | 277.546 / 277.738 | 278.607 / 281.328 |
| minimal 100000 | 0.010 / 0.010 | 0.010 / 0.009 | 4.969 / 4.962 | 4.998 / 4.996 |
| memset 100000 | 0.050 / 0.049 | 0.049 / 0.053 | 4.795 / 4.796 | 4.853 / 4.971 |
| pinky 1 | 0.480 / 0.454 | 0.457 / 0.458 | 81.280 / 79.369 | 82.020 / 79.277 |
| init 0 | 7.564 / 7.861 | 7.846 / 8.029 | 335.740 / 344.357 | 346.906 / 343.302 |
| tick 0 | 7.580 / 7.600 | 7.622 / 7.934 | 46.685 / 46.234 | 45.834 / 49.033 |

The retained expanded witness passes again on restored native and forced-storage-refusal builds.
The accepted runtime and its prior macOS/Linux qualification remain unchanged.


## Public/core comparison controls and process variation

The accepted runtime remains byte-identical to `39aa1617ad3503185f7c353e5418b1af4186cf34`
(and accepted runtime `4af05970`). This increment changes only local comparison tooling and
its parser tests. No runtime optimization, default, dependency or CI configuration changes.

### Diagnostic separation

An ignored combined driver ran public execution, a retained frame and a fresh frame leasing the
same prepared stream within one executable per exact runtime revision. On long sieve, accepted
public/retained/fresh CPU medians were 292.185/292.909/291.0205 ms in forward order and
284.295/285.428/284.028 ms in reverse order. The rejected head-load trial measured
266.029/267.122/264.087 and 265.4725/267.160/266.1205 ms respectively. All three modes
have identical fragment/call/compiled-operation/code-byte counts for their own runtime. The
24 processes / 312 complete-state calls and two equal-image build pairs pass.

This does not support attributing the earlier long-loop difference to fresh invocation ownership.
Short sieve public calls add about 0.24–0.30 ms in this diagnostic; long-loop execution tracks the
other modes closely. These diagnostic numbers are tied to that combined executable and cannot
be substituted into the maintained public/reference timing table.

The application harness also compiled only the candidate public role with
`pvmArm64JitOwnerReceipt`; the baseline omitted it. A separate receipt-on/off matrix over both
exact revisions uses identical public drivers: four equal-image build pairs and sixteen processes /
208 complete-state calls pass. Results vary by build and process order; they do not establish
a stable head-load win. No hardware counters were collected and no CPU/cache/predictor cause
is inferred. The rejected runtime remains absent.

### Matched public comparison protocol

`matched-owner-v1` now compiles baseline and candidate public JIT roles with identical feature
defines and requires the same complete native-owner receipt from both. Strict full-state and
DOOM lifecycle parsing remains mandatory. When source cohorts are identical, the harness also
requires byte-identical baseline/candidate kernel and DOOM executables before timing. Older
reports retain their original framing and exact helper identities; this protocol applies to new runs.

The full A/A cohort uses baseline `39aa1617` and the unchanged working runtime. Both public
source cohorts and both executable families are byte-identical. Six stable native counters
(fragments, calls, compiled guest operations, code bytes, conditional entries and direct-header
entries) match across the two public roles for all workloads and both process orders.
Compilation CPU is a clock and is checked separately from those deterministic counters.

CPU ms, forward / reverse. These A/A rows demonstrate measurement variation with identical
engines. Public calls include fresh memory and immutable publication.

| Case | Public baseline JIT | Public candidate JIT | Candidate / baseline |
|---|---:|---:|---:|
| sieve 100000 | 2.804 / 2.893 | 2.793 / 2.882 | 0.996 / 0.996 |
| sieve 10000000 | 291.229 / 281.786 | 308.877 / 283.476 | 1.061 / 1.006 |
| minimal 100000 | 4.907 / 5.077 | 4.950 / 5.066 | 1.009 / 0.998 |
| memset 100000 | 3.478 / 3.651 | 3.452 / 3.564 | 0.992 / 0.976 |
| pinky 1 | 76.526 / 78.483 | 78.216 / 78.459 | 1.022 / 1.000 |
| init 0 | 324.489 / 323.416 | 326.892 / 323.800 | 1.007 / 1.001 |
| tick 0 | 37.812 / 37.965 | 37.757 / 37.852 | 0.999 / 0.997 |

Long sieve differs by about 5.1% in one A/A process order and 0.6% in the reverse order.
Twenty additional same-image long-sieve processes (260 fully checked calls), in five balanced
ABBA blocks, yield baseline process-median range 276.876–280.9005 ms and aggregate median
279.56525 ms; the other role ranges 277.1515–285.454 ms with aggregate median 278.38725 ms.
The aggregate difference is about 0.4% and the distributions overlap. A single process pair or
a retained-core delta cannot establish a small public-call improvement here. Future timing
verdicts require repeated process-level pairs when observed variation is material to the claimed gain.

### Qualification and next bounded work

The matched full cohort passes 70 processes / 910 complete-state calls / 115 positive and
refusal controls / sixteen fresh builds (eight equal-image pairs). Independent re-parsing checks
all 710 source/helper/input/compiler/image seals, exact baseline source bytes, both cross-role
image equalities and all stable native counters. All twelve affected parser tests pass.
The repeated A/A cohort checks unchanged sealed inputs and images before every process.
No new Linux result is claimed: production bytes remain identical to the previously qualified runtime.

Records are under `build/pvm-arm64-jit/boundary-investigation` and the maintained
`build/tests/pvm-arm64-applications` report. Rejected head-load application receipts were moved
to `build/pvm-arm64-jit/head-load/trial-applications` before the fresh cohort. Diagnostic-only
runner failures (an incorrect constructor name and an omitted required sample setting) were fixed
without changing production behavior or weakening the drivers; the original diagnostics remain.

The next bounded coverage candidate is pure register comparisons and multiply-high operations.
The prior counts show 182,782 native returns to opcode136 and 105,420 to opcode214 on Pinky.
Those counts identify a boundary to investigate; they do not establish a prospective CPU gain.
A future trial must preserve alias/signedness/budget witnesses and pass matched repeated public
measurements before retention. No further lowering was mixed into this measurement increment.


## Comparison and multiply-high native coverage: retained

This isolated increment adds six pure comparison opcodes 136/137/142/143/216/217 and three
upper-product opcodes 213/214/215, increasing native register coverage from 44 to 53 opcodes.
The sixteen existing conditional branch opcodes are unchanged. Accepted parent:
`c81bac056458f28b4249ba4ea4b2b6912b3050c8`. The matched-owner comparison protocol is used
for both public JIT roles. No memory/host/source-attempt/pricing/ownership/ABI/cache-cap,
default, CLI, CI or dependency changes. The rejected checked-load trial remains absent.

Comparisons emit CMP followed by a zero-extending Boolean CSET. Signed and unsigned upper
products use SMULH and UMULH. Signed-by-unsigned upper multiplication computes sign(A)&B
before either source can be overwritten, then subtracts it from UMULH. The resident register
file and dirty-slot publication remain unchanged; aliased operands retain pre-mutation values.
Exact encodings were checked against the local assembler before qualification.

Independent literal products were frozen from unbounded integer multiplication over 64 operand
pairs, including zero, one, two, signed extrema, all ones, cross-halfword carries and mixed bits.
The expected upper word is `(product >> 64) & (2^64-1)` with each input signed only for the
selected operation. Sign-key ordering supplies independent comparison expectations. The witness
checks 1,640 upper-product/register-comparison cases, 432 immediate comparisons, 2,120 cases
over all 53 native register opcodes, and 576 new mixed source-budget/gas boundaries. Existing
constant, branch-predicate, memory, host, source-owner, move/copy and 10,560 control cases remain.
All of these pass on native and forced-storage-refusal paths on both macOS and Linux ARM64.

### Retention verdict from repeated public calls

Apple M1 Max, pinned October 26 Nimony 358b9bce, checked release/ARC/Clang ThinLTO.
Five balanced ABBA blocks per workload supply ten independent processes per public JIT role.
Each process checks 13 complete calls; reused medians exclude its cold first call. Our public
calls include fresh invocation memory and immutable publication. No competing builds run in
this timing phase. These are measured process CPU clocks; no hardware counters were collected.

Repeated public CPU ms: ten independent processes per role, five balanced ABBA blocks.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.893 (2.856–2.919) | 2.913 (2.860–2.944) | 1.007 | 1.009, 1.005, 0.994, 1.021, 1.006 |
| minimal 100000 | 4.955 (4.897–5.003) | 4.947 (4.903–5.045) | 0.998 | 1.002, 0.996, 1.010, 0.996, 1.003 |
| memset 100000 | 3.627 (3.538–3.676) | 3.599 (3.554–3.683) | 0.993 | 1.016, 1.000, 0.996, 0.981, 0.982 |
| pinky 1 | 77.946 (77.311–78.662) | 73.803 (73.118–75.417) | 0.947 | 0.947, 0.944, 0.945, 0.955, 0.948 |
| sieve 10000000 | 273.494 (272.408–274.722) | 272.627 (271.198–277.806) | 0.997 | 1.001, 0.997, 0.994, 0.991, 1.008 |
| init 0 | 321.082 (319.197–321.942) | 320.511 (318.085–323.026) | 0.998 | 0.999, 0.998, 0.998, 1.000, 1.005 |
| tick 0 | 37.677 (37.501–38.165) | 37.555 (37.120–38.986) | 0.997 | 0.996, 0.995, 0.987, 0.992, 1.025 |

Pinky improves about 5.3%: every block ratio is 0.944–0.955, and the ten-process ranges do not
overlap. This is the useful retained gain. Other aggregate deltas remain within about 0.7%;
short sieve is about 0.7% slower with overlapping ranges, so no material regression is established.
The full ordinary cohort had an inconsistent Pinky reverse-order sample (73.896/80.674ms);
the repeated process cohort, rather than a selected favorable sample, determines retention.
No additional speed gain is claimed for sieve, minimal, fill or DOOM.

### Same-cohort interpreter/reference comparison

This separate full cohort preserves both process orders. CPU ms, forward / reverse. Reference
raw calls exclude restoration and teardown; their separate DOOM lifecycle receipts are checked.
Retained-core execution has a separate reset/publication scope. Ratios in this table use only
this cohort; repeated-process timings above are never paired with these reference clocks.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.579 / 3.509 | 2.873 / 2.838 | 2.865 / 2.853 | 2.833 / 2.819 | 6.095 / 6.046 | 0.800 / 0.813 | 0.470 / 0.472 |
| minimal 100000 | 5.056 / 4.971 | 4.987 / 4.965 | 5.062 / 4.951 | 4.971 / 4.911 | 6.094 / 6.045 | 1.001 / 0.996 | 0.831 / 0.819 |
| memset 100000 | 4.503 / 4.470 | 3.628 / 3.555 | 3.590 / 3.602 | 2.821 / 2.821 | 4.045 / 4.030 | 0.797 / 0.806 | 0.887 / 0.894 |
| pinky 1 | 87.542 / 86.228 | 77.306 / 78.925 | 73.896 / 80.674 | 73.976 / 74.007 | 95.863 / 95.865 | 0.844 / 0.936 | 0.771 / 0.842 |
| sieve 10000000 | 340.553 / 343.040 | 278.419 / 281.200 | 280.389 / 281.896 | 293.880 / 297.598 | 372.663 / 370.728 | 0.823 / 0.822 | 0.752 / 0.760 |
| init 0 | 325.083 / 325.586 | 320.377 / 321.908 | 319.843 / 323.312 | 323.724 / 323.074 | 684.298 / 681.603 | 0.984 / 0.993 | 0.467 / 0.474 |
| tick 0 | 41.332 / 40.836 | 37.925 / 37.794 | 37.908 / 37.580 | 34.398 / 34.412 | 44.688 / 45.148 | 0.917 / 0.920 | 0.848 / 0.832 |

### Constructor and cold costs

CPU ms, forward / reverse. Owner constructors are outside public call clocks; cold calls
include lazy preparation and native compilation/publication. These are individual first-call
observations, not repeated cold-start performance claims.

| Case | Parent constructor | New constructor | Parent cold call | New cold call |
|---|---:|---:|---:|---:|
| sieve 100000 | 1.603 / 1.583 | 1.632 / 1.583 | 8.206 / 7.921 | 8.158 / 8.209 |
| sieve 10000000 | 1.636 / 1.677 | 1.611 / 1.601 | 284.870 / 287.781 | 288.072 / 285.433 |
| minimal 100000 | 0.011 / 0.010 | 0.011 / 0.011 | 4.969 / 5.067 | 5.115 / 5.008 |
| memset 100000 | 0.052 / 0.053 | 0.051 / 0.054 | 5.108 / 4.739 | 5.122 / 5.009 |
| pinky 1 | 0.465 / 0.547 | 0.483 / 0.514 | 80.148 / 88.113 | 76.734 / 76.746 |
| init 0 | 7.928 / 8.128 | 7.779 / 7.805 | 340.126 / 343.801 | 338.637 / 342.243 |
| tick 0 | 7.898 / 8.689 | 7.788 / 7.666 | 50.366 / 45.794 | 50.364 / 47.450 |

### Native coverage and cache observations

In the full cohort Pinky native fragments rise 514→518 and emitted bytes 44,092→47,884.
Compiled guest operations over 13 calls rise137,037,306→165,076,876; native calls rise
30,828,356→31,512,494 and checked direct-header entries 12,564,678→13,669,609. Conditional
entry counts remain 21,030,402. Native compilation/publication CPU is 0.839/0.976ms at parent
and 0.824/0.928ms in the trial. These are compiled guest-operation counts, not executed hardware
instruction counts, and they do not establish a particular CPU mechanism for the timing gain.

DOOM initialization still reaches the unchanged 1,024-fragment cap and uses checked fallback.
Its emitted bytes change 79,904→82,664; compilation/publication is 3.917/3.856→4.018/3.844ms.
Gameplay occupancy rises 720→736 fragments and 52,748→55,504 emitted bytes, with compilation
1.204/1.244→1.331/1.209ms. Wider native coverage therefore costs some code bytes without a
measured useful DOOM gain in this increment. The one-MiB arena and all resource ceilings remain.

### Qualification and provenance

Mac qualification passes nine native gates, 42 kernel processes/546 checked calls/63 controls/
six fresh builds (three equal-image pairs), and 70 application/core/reference processes/910
checked calls/115 controls/sixteen fresh builds (eight equal-image pairs). Independent re-parsing
checks all 706 kernel and 710 application seals plus exact accepted-parent source identity.
The repeated cohort adds 140 public processes/1,820 checked calls, bound to the full-cohort
source/input/compiler/image seals. Six stable native-counter fields match within each of its 14
workload/role groups across all ten processes. All full CPU/gas/register/page/permission/source
snapshots and ordered host events remain checked.

Fresh isolated Linux ARM64 Docker qualification also passes: nine shared gates with all expanded
witnesses, four public builds, 14 processes/182 checked calls and 32 controls. Independent
verification re-parses all calls, checks 2,863 staged source/fixture seals, executable hashes and
the compiler binary against the official pinned Linux ARM64 archive. Linux container clocks
remain diagnostic only. Image: `sha256:c945183d805785e5999a334bffb3b662f1930852a8639df1f48d53655681093b`.

Receipts are under `build/pvm-arm64-jit/register-coverage`, the corresponding
`build/tests/pvm-arm64-jit` and `build/tests/pvm-arm64-applications` reports, and
`build/pvm-arm64-jit/linux`. The preceding A/A cohort moved to
`build/pvm-arm64-jit/boundary-investigation/aa-applications`; earlier Linux evidence moved to
`build/pvm-arm64-jit/register-coverage/prior-linux`. No originating native/benchmark failure
required a production correction in this increment. The emitted implementation is retained in
the existing draft for further local work; it is not a default or merge recommendation.


## Remaining boundary profile after 53-opcode coverage

Profiled runtime: `1003f8f7c0f54326d0f2a5f220b6eb9a281e9ead`. All instrumentation lives in
ignored source snapshots; production code and benchmark timing images are unchanged. Each of the
seven fixtures executes once cold and once with its retained stream. Additional DOOM shape and
admission probes execute the same two-call pattern. All 22 calls retain complete reference CPU,
gas, memory/permission, source-snapshot and ordered host-event checks. Every diagnostic clock
is discarded. These are logical operation/transition counts, not hardware counters or sampled CPU
costs. Register counts include arithmetic in inline fused/charged interpreter workers; they are
not counts of separate function dispatches.

| Workload | Memory visits | Interpreted register visits | Missing register-opcode visits |
|---|---:|---:|---:|
| sieve 100000 | 119,665 | 283,652 | 81 |
| sieve 10000000 | 15,475,522 | 31,283,927 | 462 |
| pinky 1 | 8,066,877 | 6,030,323 | 488,059 |
| memset 100000 | 300,101 | 109 | 11 |
| minimal 100000 | 1,000,015 | 600,011 | 0 |
| init 0 | 8,145,614 | 118,652,603 | 7,980 |
| tick 0 | 4,126,674 | 4,113,547 | 16,627 |

### Highest-priority candidate: conditional publication and admission

DOOM initialization's five hottest arithmetic sites already have native opcode support:

| Source PC | Opcode | Reused interpreted visits |
|---|---:|---:|
| 193987 | add64 (200) | 21,304,033 |
| 193990 | logical right32 (139) | 21,304,033 |
| 193996 | add immediate32 (131) | 21,295,001 |
| 194002 | logical left immediate64 (151) | 21,303,767 |
| 194005 | logical right immediate64 (152) | 21,303,767 |

These total 106,510,601 operations per call. Exact handler probes identify the existing three
specialized charged-shape headers at PCs 193987/193996/194002; their first bodies are not native
pending, native branch or native arithmetic handlers. The lazy compilation trace reaches each
header/body pair with zero prior entry and a full 1,024-publication count. The absent native body
therefore has direct admission evidence; this is not inferred from opcode support alone.

Initialization retains 774 active native entries after 1,024 publications: 250 older publications
are superseded by later versions at the same entry. The two publication call sites are initial
arithmetic emission and conditional promotion. The unchanged counter/limit counts both versions.
Only 82,664 bytes of the one-MiB arena are used in this fixture. Gameplay has 467 active entries
after 736 publications, including 269 superseded publications, and does not reach the cap.

The next bounded experiment should publish a complete conditional fragment once its original
checked branch worker has positively cached both scalar destinations, retaining checked
interpreter execution before that point. This can recover publication budget without raising
limits or adding eviction. Specialized charged headers must hand off coherently when a native
body becomes available; otherwise an already-compiled body could remain bypassed. Preserve
partial-budget/gas behavior, invalid-target ordering, OS/capacity refusal and exact owner transfer.

The hypothesis is improved admission of later hot supported code, especially the initialization
loop. Recovered budget does not prove that loop will be admitted or faster: the existing Nim
three-shape cycle is already fused, and small native leaves may lose to it. Qualification must
check actual header/body selection, full state and repeated public timings before retention.
No runtime or cap change is included in this profiling increment.

### Other bounded candidates

Pinky's remaining unsupported register work is exactly six opcodes. Conditional moves 218/219
account for 191,513/151,705 visits, totaling 343,218 (about 70.3% of unsupported register visits).
Alternative immediate shifts 147/148 account for 61,383/41,040 visits; leading-zero operations
104/103 contribute 36,548/5,870. Conditional-move lowering is the next small pure-register
coverage candidate, with explicit old-destination live-in and destination/source-alias tests.
These visit counts do not establish a prospective CPU gain.

DOOM gameplay has only 16,627 unsupported register visits; 16,509 are signed division32
(opcode 194). Its larger boundary is short supported arithmetic around memory: the pixel-loop
site 530670 executes logical right32 (198) 1,024,000 times, followed by byte store 120 at
site 530673 the same number of times. Native branch returns land at that shift site 768,000
times. The current fragment floor and memory boundary leave this short sequence interpreted.
A later checked register/memory-loop experiment should target that pattern with exact prefix
publication and refusal behavior; adding division alone is a much smaller coverage change.

Long sieve still performs 15,475,522 memory visits. Source 156874 performs a 64-bit load
5,000,000 times followed by three supported operations and a static jump. Memory fill has
199,998 byte stores at source 1913; minimal has 1,000,015 memory visits and 200,001 dynamic
transfers while its missing-register count is zero. None of these suggests broad arithmetic
coverage as the main remaining boundary. All seven workloads have zero full slow-load/store
fallback hits: accesses satisfy the existing contiguous-region fast checks. This observation
does not authorize weakening those checks or resurrecting the previously rejected head-load trial.

### Diagnostic provenance

The main probe counts interpreter register equations at all six worker/template call sites, memory
workers and region paths, scalar control workers, arithmetic-leaf returns and native branch
landing sites. Counts are reset between cold/reused calls while native source/stream ownership
remains retained. The DOOM follow-ups inspect exact header/body identities, active entry maps
and late admission context. Snapshot hashes are independently checked for all three successful
probes (478 files each); all 710 source/helper/input/compiler/image seals of the qualified
application cohort remain unchanged. No Linux timing/profile or hardware-cause claim is added.

Records: `build/pvm-arm64-jit/expanded-boundaries/{results,shapes,admission}.json`, their sealed
snapshots and `independent-verification.json`. Four diagnostic images execute eleven processes /
22 checked calls. The first active-entry dump used a reference-container iterator rejected by
the pinned compiler; an index loop fixes that diagnostic without a hidden sequence copy. Its
failed source and originating log remain preserved. Production implementation and existing
macOS/Linux qualification remain unchanged.

## Single-publication conditional admission trial — rejected (October 27)

Measured prototype `a4adf513f92947a60cabb119abd9a4777ca4e232` against accepted parent
`baa94af2026ec0a63c6b6e0a2bee2aa0847416de` on Apple M1 Max with the unchanged pinned
October 26 compiler, ARC, checked release and Clang ThinLTO. The final runtime is restored to
that parent; its accepted 53 register operations and 16 conditional operations remain unchanged.

The trial deferred conditional executable publication until the original branch had positively
cached both scalar destinations. It stored only the terminal coordinate before admission, used
original checked handlers for first/partial execution and restored them on publication refusal.
Three specialized cold charged headers kept pending bodies reachable and could hand off after
admission. Neither cache ceiling, memory checks, quotas, source ownership nor host semantics changed.

### Paired public/core results

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.434 / 3.460 | 2.787 / 2.869 | 2.826 / 2.853 | 2.817 / 2.872 | 5.936 / 6.022 | 0.823 / 0.825 | 0.476 / 0.474 |
| minimal 100000 | 4.921 / 4.953 | 4.913 / 4.915 | 4.891 / 4.949 | 4.859 / 4.938 | 6.020 / 6.077 | 0.994 / 0.999 | 0.813 / 0.814 |
| memset 100000 | 4.386 / 4.320 | 3.501 / 3.541 | 3.449 / 3.483 | 2.752 / 2.758 | 3.957 / 3.978 | 0.786 / 0.806 | 0.872 / 0.876 |
| pinky 1 | 86.297 / 85.631 | 72.911 / 72.438 | 72.320 / 72.674 | 72.410 / 73.207 | 94.091 / 94.484 | 0.838 / 0.849 | 0.769 / 0.769 |
| sieve 10000000 | 339.164 / 337.423 | 278.269 / 276.635 | 280.761 / 281.149 | 291.303 / 293.496 | 366.476 / 368.824 | 0.828 / 0.833 | 0.766 / 0.762 |
| init 0 | 323.765 / 325.248 | 320.420 / 320.440 | 503.323 / 503.398 | 508.144 / 500.099 | 674.673 / 674.621 | 1.555 / 1.548 | 0.746 / 0.746 |
| tick 0 | 40.304 / 41.642 | 37.081 / 37.617 | 37.144 / 37.403 | 33.849 / 33.903 | 45.110 / 44.406 | 0.922 / 0.898 | 0.823 / 0.842 |

Reference is PolkaVM interpreted call CPU; it excludes its separate restoration/teardown.
Public calls include private invocation memory and immutable output publication. Retained core
has its separate reset/publication lifecycle and does not establish a public-call gain.

### Owner construction and first call

CPU ms, forward / reverse. First calls include cold preparation and native publication.

| Case | Previous owner | Trial owner | Previous cold call | Trial cold call |
|---|---:|---:|---:|---:|
| sieve 100000 | 1.607 / 1.651 | 1.587 / 1.633 | 7.821 / 8.304 | 7.826 / 8.013 |
| minimal 100000 | 0.010 / 0.010 | 0.009 / 0.010 | 5.094 / 5.053 | 4.911 / 5.008 |
| memset 100000 | 0.059 / 0.060 | 0.053 / 0.051 | 4.952 / 5.020 | 4.866 / 4.887 |
| pinky 1 | 0.457 / 0.454 | 0.465 / 0.467 | 75.923 / 75.475 | 76.049 / 76.535 |
| sieve 10000000 | 1.609 / 1.631 | 1.618 / 1.599 | 288.315 / 288.391 | 293.205 / 284.530 |
| init 0 | 7.706 / 8.449 | 7.671 / 7.957 | 341.161 / 343.842 | 519.811 / 542.634 |
| tick 0 | 7.686 / 8.070 | 7.744 / 7.700 | 46.760 / 47.627 | 47.785 / 47.624 |

### Repeated public-call verdict

Repeated public CPU ms: ten independent processes per role, five balanced ABBA blocks.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.813 (2.796–2.926) | 2.857 (2.820–2.948) | 1.016 | 1.015, 1.019, 0.996, 1.006, 1.024 |
| minimal 100000 | 4.869 (4.827–4.916) | 4.878 (4.853–4.897) | 1.002 | 1.003, 0.999, 1.007, 1.004, 0.997 |
| memset 100000 | 3.482 (3.433–3.627) | 3.480 (3.446–3.529) | 0.999 | 1.000, 0.972, 1.007, 1.000, 1.007 |
| pinky 1 | 73.072 (72.141–74.731) | 72.683 (72.067–76.284) | 0.995 | 0.994, 0.985, 0.999, 0.998, 1.016 |
| sieve 10000000 | 273.750 (271.958–275.779) | 272.851 (271.564–276.935) | 0.997 | 0.998, 1.000, 0.998, 1.004, 0.992 |
| init 0 | 321.008 (316.704–323.709) | 508.433 (503.234–513.154) | 1.584 | 1.590, 1.574, 1.592, 1.580, 1.587 |
| tick 0 | 37.483 (37.325–37.797) | 37.357 (37.105–37.874) | 0.997 | 0.988, 1.002, 1.004, 0.999, 0.991 |

The initialization regression is consistent across all five balanced blocks (trial/parent
1.574–1.592), with non-overlapping process ranges. Other medians are within 1.6%, with
overlapping ranges; no smaller benefit is claimed. Reject the complete runtime experiment.

Admission did improve: initialization has 1,024 active entries for 1,024 publications instead
of 774 active entries for 1,024 publications. The exact header/body diagnostic confirms native
handoff at source PCs 193987 and 194002; 193996 remains interpreted. Gameplay has 426 active
entries/publications after reuse. These are bounded cache observations, not hardware counters.

Across the thirteen initialization calls, native calls increase from 21,252,751 to 583,159,301
and lowered guest operations from 72,240,971 to 1,770,509,491. Source inspection shows that the
new handoffs replace the already fused three-shape interpreter cycle with many small native
calls. Greater native coverage is therefore not a useful objective by itself. Counts and timings
support rejecting this boundary arrangement; no specific hardware cause is inferred.

### Checks and provenance

All nine native gates passed, including full opcode/host state, forced refusal and exclusive
owner move/copy controls. The focused warmed-loop witness verified one final publication.
The full kernel cohort passed 42 processes / 546 calls / 63 controls / six fresh builds and
three equal-image pairs; the application cohort passed 70 processes / 910 calls / 115 controls /
sixteen fresh builds and eight equal-image pairs. Independent verification reparsed all logs
and checked 706/710 seals, exact parent sources and image equality. All 140 additional repeated
processes / 1,820 calls were independently reparsed against the sealed application cohort.
Measured tracked sources match the preserved prototype commit (684 kernel / 667 application files).

An isolated untimed diagnostic adds two processes/four complete DOOM calls; all its snapshot
hashes are checked. Its clocks are discarded. No Linux performance claim or new Linux runtime
qualification is needed for this rejected implementation. Restored native/refusal witnesses
and exact source equality are recorded separately after the reversal.

The first build required an explicit non-null proof for restoring the original handler.
The pinned formatter then joined the multiline header predicate into an invalid token; using
a named predicate and formatting before the final cohort resolved it. Failed build logs remain
with the experiment; only the completed final cohorts support this verdict.

Records: `build/pvm-arm64-jit/single-publication/` (prior accepted receipts, repeated-public
cohort, admission snapshot, failed/final logs, restored checks); measured current cohorts in
`build/tests/pvm-arm64-{jit,applications}/` each include independent verification and preserving
commit receipts. The comparison helper retains the updated exact accepted-parent pin.

Next bounded candidate: conditional moves 218/219 inside already admitted register fragments,
with explicit old-destination live-in and alias checks. This extends useful work per existing
handoff while leaving the successful charged interpreter cycle intact. No next lowering is
included here.

## Conditional-move coverage trial — rejected (October 27)

Measured prototype `a578fe46a65835b10c43acab54db9a9cb83495fb` against accepted parent
`290f3bf78cea8b4a938732e686e38bed8c22f393`, Apple M1 Max with the same pinned checked
ARC/Clang ThinLTO build. Added opcodes218/219 using CMP/CSEL, explicitly reading the
old destination before declaring its write. Independent960literal predicate/value/alias cases,
55-opcode register matrix2,200cases and672mixed partial-budget cases passed.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.560 / 3.462 | 2.827 / 2.887 | 3.055 / 3.110 | 2.636 / 2.642 | 5.974 / 5.950 | 0.858 / 0.898 | 0.511 / 0.523 |
| minimal 100000 | 4.920 / 4.915 | 4.894 / 4.888 | 4.915 / 4.870 | 4.896 / 4.931 | 6.065 / 6.006 | 0.999 / 0.991 | 0.810 / 0.811 |
| memset 100000 | 4.476 / 4.431 | 3.607 / 3.575 | 3.579 / 3.534 | 2.796 / 2.777 | 3.988 / 3.953 | 0.800 / 0.798 | 0.897 / 0.894 |
| pinky 1 | 86.183 / 85.775 | 72.661 / 72.671 | 72.999 / 72.859 | 72.566 / 72.135 | 95.333 / 94.436 | 0.847 / 0.849 | 0.766 / 0.772 |
| sieve 10000000 | 337.733 / 340.305 | 276.752 / 278.575 | 293.428 / 295.614 | 276.431 / 276.226 | 369.017 / 368.579 | 0.869 / 0.869 | 0.795 / 0.802 |
| init 0 | 322.702 / 326.245 | 319.043 / 321.355 | 321.611 / 319.262 | 321.060 / 320.029 | 677.189 / 675.370 | 0.997 / 0.979 | 0.475 / 0.473 |
| tick 0 | 40.531 / 40.456 | 37.298 / 37.678 | 37.996 / 37.833 | 34.792 / 34.868 | 44.440 / 44.706 | 0.937 / 0.935 | 0.855 / 0.846 |

Repeated public CPU ms: ten independent processes per role, five balanced ABBA blocks.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.854 (2.838–2.883) | 3.075 (3.042–3.095) | 1.077 | 1.076, 1.069, 1.078, 1.078, 1.072 |
| minimal 100000 | 4.934 (4.901–4.963) | 4.932 (4.900–4.965) | 1.000 | 0.995, 1.005, 0.998, 1.006, 0.997 |
| memset 100000 | 3.621 (3.540–3.674) | 3.561 (3.523–3.628) | 0.983 | 0.983, 0.977, 0.987, 1.002, 0.989 |
| pinky 1 | 72.534 (72.225–73.031) | 72.542 (72.195–72.688) | 1.000 | 1.001, 0.997, 0.997, 1.001, 0.999 |
| sieve 10000000 | 273.174 (272.558–275.401) | 294.344 (292.599–295.950) | 1.077 | 1.075, 1.072, 1.081, 1.073, 1.074 |
| init 0 | 320.662 (318.479–322.304) | 321.812 (318.940–325.090) | 1.004 | 1.001, 1.000, 1.002, 1.005, 1.009 |
| tick 0 | 37.612 (37.370–37.758) | 38.215 (37.837–38.414) | 1.016 | 1.006, 1.020, 1.020, 1.014, 1.016 |

Repeated public sieve100k and10m regress7.7%, consistently across all five balanced blocks,
with non-overlapping process ranges. Pinky is unchanged. Retained-core sieve improved in
the initial kernel cohort, which does not establish a public-call gain. Public sieve100k
native calls differ by only13over13calls, and lowered operations by52; no hardware or
code-layout cause is inferred. Reject this isolated runtime addition and restore53-opcode
coverage before the connected-loop trial. The native instruction implementation and witnesses
remain preserved in the measured prototype for revisiting after the execution-boundary work.

All nine native gates passed; kernel42processes/546calls/63controls/6freshbuilds/3equal-image
pairs and application70processes/910calls/115controls/16builds/8pairs independently verified
706/710seals. Repeated140processes/1,820calls were independently reparsed against sealed
images/inputs. Exact tracked source hashes match the preserving commit. No Linux run is
claimed for the rejected variant; the restored runtime equals the previously qualified parent.
Owner/first-call raw clocks remain in the complete application receipt. Records:
`build/pvm-arm64-jit/conditional-moves/` and the current sealed kernel/application cohorts.

## Connected charged-loop execution — retained (October 27)

Measured runtime `973c2f6d04920b438e14c109d1998b99b9918140` against accepted parent
`1521566105e94e3eb667b85535ec94627db34937`, whose runtime is the accepted 53-register-opcode
implementation. The conditional-move trial above remains rejected; its measurements and
correct implementation are preserved for revisiting after further execution-boundary work.
Both sides use the pinned October 26 compiler, ARC, Clang ThinLTO and enabled checks.

### Bounded execution model

After the existing interpreter completes an actual closed round through three positively cached
charged shapes, it may publish one connected register-only loop. This initial region targets
the existing 200/139/82 →131/88 →151/152/173 shape cycle in any entry rotation; it is not
a general program-wide graph compiler. Every arithmetic operation and both scalar branch arms
come from checked immutable plan facts and original cached branch workers.

All thirteen guest registers remain resident across internal branches. X0 borrows the current
register array; X17 borrows a fresh invocation-local context; X2/X3 hold gas/source attempts,
and X1 is scratch. Generated code changes neither SP/LR nor callee-saved registers. No guest
memory access or host callback runs natively; no invocation/guest/source pointer is cached.
All registers are live on entry and published on exit, avoiding unsound linear live-in analysis
when a path skips a definition. Native edges are bounded relative branches inside one immutable
image, or captured scalar returns to the checked stream.

Each block first checks its whole source span, then unsigned gas sufficiency; only a complete
block debits either counter. If the block cannot run completely, the original checked header
receives its untouched state and preserves exact zero-budget/gas/partial-prefix precedence,
PC, paid flags and temporary barriers. Incoming paid state, active barriers, changed scalar
charges or non-dynamic pricing use original workers. Every completed branch clears paid state.
The invocation context also counts block visits; checked return accounting verifies that their
sealed spans exactly equal consumed source attempts. These are guest-work counts, not CPU counters.

The source-bound cache retains one connected region and three scalar headers/prices/spans.
One of the existing 1,024 publication slots is reserved for that region (ordinary leaves stop
at1,023); the total remains1,024 and one MiB. Its image contains at most1,024words including return, with up to64
source nodes per scanned block and source spans limited to the immediate-encoding bound.
OS/capacity refusal preserves the original fused interpreter cycle. Only the observed root
changes dispatch; originals for all three guard returns survive exact-owner stream transfer.

### Qualified public and reference CPU timings

Apple M1 Max, CPU ms, forward / reverse process order. Public calls include fresh invocation
memory and immutable publication. Retained core has separate reset/publication costs.
Reference is PolkaVM interpreted call CPU; its restoration/teardown lifecycle remains separate.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.451 / 3.462 | 2.795 / 2.802 | 2.821 / 2.849 | 2.816 / 2.813 | 6.026 / 6.182 | 0.817 / 0.823 | 0.468 / 0.461 |
| minimal 100000 | 4.905 / 4.912 | 4.887 / 4.904 | 4.904 / 4.893 | 4.904 / 5.054 | 6.013 / 6.147 | 1.000 / 0.996 | 0.816 / 0.796 |
| memset 100000 | 4.548 / 4.447 | 3.497 / 3.567 | 3.494 / 3.531 | 2.765 / 2.792 | 3.957 / 3.942 | 0.768 / 0.794 | 0.883 / 0.896 |
| pinky 1 | 85.004 / 85.960 | 72.623 / 72.424 | 72.641 / 72.758 | 72.880 / 73.606 | 94.986 / 94.722 | 0.855 / 0.846 | 0.765 / 0.768 |
| sieve 10000000 | 336.659 / 336.869 | 275.550 / 278.204 | 277.293 / 278.238 | 293.017 / 294.336 | 367.421 / 368.120 | 0.824 / 0.826 | 0.755 / 0.756 |
| init 0 | 325.486 / 323.928 | 320.209 / 317.223 | 230.120 / 227.960 | 232.913 / 227.567 | 690.681 / 676.375 | 0.707 / 0.704 | 0.333 / 0.337 |
| tick 0 | 40.562 / 40.416 | 38.092 / 37.319 | 37.801 / 37.575 | 34.547 / 33.906 | 44.934 / 44.466 | 0.932 / 0.930 | 0.841 / 0.845 |

Owner construction and first call, CPU ms, forward / reverse:

| Case | Previous owner | Connected owner | Previous cold call | Connected cold call |
|---|---:|---:|---:|---:|
| sieve 100000 | 1.580 / 1.701 | 1.604 / 1.727 | 7.843 / 7.646 | 7.734 / 8.102 |
| minimal 100000 | 0.012 / 0.015 | 0.012 / 0.011 | 5.065 / 4.968 | 4.963 / 5.012 |
| memset 100000 | 0.049 / 0.051 | 0.057 / 0.055 | 4.729 / 4.913 | 4.903 / 5.245 |
| pinky 1 | 0.451 / 0.457 | 0.458 / 0.481 | 76.026 / 76.165 | 76.325 / 75.330 |
| sieve 10000000 | 1.567 / 1.598 | 1.606 / 1.634 | 281.216 / 283.113 | 282.461 / 283.850 |
| init 0 | 7.785 / 7.740 | 7.735 / 7.584 | 340.224 / 336.414 | 246.028 / 246.541 |
| tick 0 | 7.825 / 7.759 | 7.847 / 7.711 | 47.572 / 47.998 | 47.401 / 47.534 |

All recognition, descriptor preparation, code generation/publication and execution are inside
the first-call CPU clock. The dedicated compilation counter times region image generation/
publication after descriptor extraction; it is not the complete first-call preparation cost.
Reference module construction and our immutable prepared-owner construction remain separate.
No combined constructor/call or cross-runner ratio is inferred.

### Balanced process repeats

Repeated public CPU ms: ten independent processes per role, five balanced ABBA blocks.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.842 (2.817–3.115) | 2.843 (2.830–2.885) | 1.000 | 1.007, 1.001, 0.959, 1.003, 1.004 |
| minimal 100000 | 4.885 (4.835–4.932) | 4.905 (4.893–4.941) | 1.004 | 1.005, 1.006, 1.008, 1.007, 1.002 |
| memset 100000 | 3.542 (3.455–3.575) | 3.510 (3.473–3.600) | 0.991 | 1.004, 1.002, 1.002, 0.981, 0.988 |
| pinky 1 | 72.104 (71.945–72.819) | 71.911 (71.629–72.832) | 0.997 | 0.995, 1.002, 0.998, 1.003, 0.991 |
| sieve 10000000 | 275.173 (271.953–280.313) | 273.320 (270.695–274.375) | 0.993 | 0.994, 0.983, 0.996, 0.990, 0.995 |
| init 0 | 321.013 (317.849–323.528) | 230.957 (229.090–232.657) | 0.719 | 0.721, 0.720, 0.718, 0.720, 0.719 |
| tick 0 | 37.521 (37.309–39.317) | 37.673 (37.463–39.315) | 1.004 | 0.992, 1.011, 1.005, 1.010, 1.003 |

Initialization improves28.1%, with every balanced block at0.718–0.721 of the accepted parent
and non-overlapping process ranges. Other medians differ by less than1% with overlapping
ranges; no smaller gain is claimed. Retain the bounded connected-loop implementation.

Untimed retained-frame diagnostics confirm root/source headers193987,193996,194002. A reused
initialization call executes63,894,035 complete native block visits in9,032 connected entries
(about7,075 blocks per entry). Gameplay has no such region and remains on existing paths.
This directly distinguishes connected execution from the rejected many-small-handoff trial.
Across thirteen public initialization calls, ordinary-plus-connected native calls are21,370,154
versus21,252,751; lowered guest operations rise72,240,971 to2,287,273,247. Publications remain
1,024 and code bytes82,664→83,092. Counts are diagnostic source work, not hardware instructions,
branch misses or a particular CPU cause. No hardware counters were collected.

### Complete verification and provenance

All nine native gates pass on macOS and isolated Linux ARM64 Docker. New witnesses include
3,546 independent all-entry-rotation loop cases covering gas/source boundaries, paid state,
both non-root branch exits, original pricing-mode fallback, source snapshots and changed
invocation registers after exclusive owner transfer. Literal context cases check guard counts,
all preserved registers and the1,023ordinary+1connected publication ceiling; the new C bridge
also checks both borrowed arguments, null/misaligned/out-of-range refusal and scalar return ABI.
All existing139-opcode, memory/host, native predicate, forced refusal and move/copy checks remain.

macOS kernel cohort:42processes/546calls/63controls,6freshbuilds/3equal-imagepairs.
Application/core/reference cohort:70processes/910calls/115controls,16builds/8equal pairs.
Independent verifiers reparse all logs,706/710source/input/compiler/image seals and exact parent
sources. Additional140processes/1,820calls independently reparse with stable native counters
in all14workload/role groups. All684kernel/667application measured tracked-source hashes
match the preserved runtime commit. Isolated admission diagnostics add2processes/4complete
DOOM calls with sealed snapshot hashes; their clocks are discarded.

Linux:9shared gates,4public builds,14processes/182checked calls,32refusal controls and2,863
staged seals. The actual Linux compiler binary is independently verified against the pinned
official archive. Container architecture/network/image and all copied logs are checked;
2,846tracked staged files match the runtime commit. Container clocks are diagnostic only,
and do not establish a bare-metal Linux speed claim.

The first compile needed a stable non-null cache borrow in its statistics accessor; after that
the focused witness and formatted complete cohorts passed. No semantic test failure occurred.
No production default, CLI backend activation, dependency pin or JIT CI job changes.

Records: `build/pvm-arm64-jit/connected-loop/` (balanced repeats, independent admission probe,
failed/final logs and prior Linux receipts), `build/tests/pvm-arm64-{jit,applications}/`
(full independent/preserving-commit receipts), and `build/pvm-arm64-jit/linux/` (sealed Linux
context, compiler archive, environment/state and independent/preserving-commit receipts).

The next structural extension should connect further validated blocks without reintroducing
per-block interpreter calls. Memory-heavy loops still require precise native checked-memory
and fault-prefix accounting; this register-only region does not solve that boundary. Conditional
moves remain a separately measured deferred addition rather than a presumed performance gain.


## Immediate connected-block charges — retained (October 27)

Measured runtime `131779257f5db4f9826feba51dd178e5be9617fe` against accepted connected-loop
parent `01f9c6742e18cb87b97545417c85a734dddf3350`, Apple M1 Max, unchanged October26
Nimony, checked release, ARC and Clang ThinLTO. The sole runtime change encodes sealed gas
prices0..4095 directly in 64-bit CMP/SUB immediate instructions inside connected regions.
Wider unsigned prices retain the original four-halfword materialization and register comparison.
Every gas guard and source-attempt guard remains in place, including zero-price blocks.
No leaf lowering, admission, cache policy, memory access or host transition changes.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.449 / 3.469 | 2.788 / 2.796 | 2.801 / 2.812 | 2.830 / 2.821 | 5.934 / 5.992 | 0.812 / 0.811 | 0.472 / 0.469 |
| minimal 100000 | 4.904 / 4.944 | 4.893 / 4.927 | 4.888 / 4.941 | 4.896 / 4.946 | 6.048 / 6.059 | 0.997 / 0.999 | 0.808 / 0.815 |
| memset 100000 | 4.403 / 4.404 | 3.557 / 3.550 | 3.575 / 3.500 | 2.784 / 2.789 | 3.954 / 3.963 | 0.812 / 0.795 | 0.904 / 0.883 |
| pinky 1 | 85.603 / 85.800 | 72.306 / 72.257 | 72.371 / 72.678 | 73.173 / 73.581 | 94.496 / 94.762 | 0.845 / 0.847 | 0.766 / 0.767 |
| sieve 10000000 | 339.152 / 338.200 | 280.152 / 278.538 | 279.513 / 279.561 | 293.489 / 294.510 | 369.964 / 369.983 | 0.824 / 0.827 | 0.756 / 0.756 |
| init 0 | 324.474 / 321.361 | 232.761 / 228.417 | 221.015 / 220.672 | 219.145 / 218.732 | 673.874 / 673.664 | 0.681 / 0.687 | 0.328 / 0.328 |
| tick 0 | 40.075 / 40.288 | 37.281 / 37.567 | 37.068 / 37.714 | 33.749 / 33.817 | 44.418 / 44.395 | 0.925 / 0.936 | 0.835 / 0.849 |

Repeated public CPU ms: ten independent processes per role, five balanced ABBA blocks.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.854 (2.830–3.106) | 2.869 (2.822–2.910) | 1.005 | 0.996, 0.958, 1.018, 1.015, 1.003 |
| minimal 100000 | 4.954 (4.906–4.976) | 4.929 (4.875–4.996) | 0.995 | 0.997, 0.995, 1.006, 1.002, 0.988 |
| memset 100000 | 3.558 (3.503–3.571) | 3.554 (3.494–3.576) | 0.999 | 0.997, 0.992, 0.996, 1.002, 1.011 |
| pinky 1 | 72.497 (71.835–73.893) | 72.532 (71.788–73.364) | 1.000 | 0.997, 0.996, 1.003, 1.001, 1.000 |
| sieve 10000000 | 272.589 (270.987–273.504) | 271.051 (270.793–272.964) | 0.994 | 0.999, 0.996, 0.996, 0.995, 0.995 |
| init 0 | 229.960 (227.998–235.774) | 221.701 (219.623–225.412) | 0.964 | 0.963, 0.962, 0.967, 0.964, 0.960 |
| tick 0 | 37.817 (37.452–38.440) | 38.029 (37.384–39.193) | 1.006 | 1.007, 0.998, 1.011, 1.024, 0.995 |

Retain this isolated lowering: initialization improves3.6% in the repeated public cohort,
229.960→221.701ms. All five balanced blocks improve3.3–4.0%, with non-overlapping process
ranges. Other workload medians differ by at most0.6%, with overlapping ranges; no benefit or
regression is claimed for those. The native work/call counts are identical to the parent;
initialization code shrinks83,092→83,044bytes. Four constant-building instructions disappear
per qualifying native block visit. No hardware counters or hardware-cause claim is made.

Independent literal486price/quota cases cover zero,1,4095,4096,2^32 and maximum64-bit prices,
including maximum64-bit source budgets, exact gas exhaustion, partial blocks and natural exits.
They check every register, remaining gas/source budget, per-block counts and scalar destination.
The previous3,546connected-region cases and1,024-publication cap still pass. All nine native
gates pass, including complete opcode/mixed/host states, refusal and exclusive owner controls.

Kernel42processes/546calls/63controls/6freshbuilds/3equal-image pairs and public-application
70processes/910calls/115controls/16freshbuilds/8equal-image pairs passed. Independent parsers
verified706/710seals, exact accepted-parent sources and all raw logs. The extra repeated cohort
passed140processes/1,820calls; all14workload/role native-counter groups remain stable.
Measured tracked source files match the preserving runtime commit:684kernel and667application.

Constructor, first call, reused public call and retained core remain distinct scopes. Reference
DOOM calls exclude its separately recorded restoration/teardown lifecycle. Full raw receipts
and clocks remain under `build/pvm-arm64-jit/region-immediates/` and current sealed kernel/app
folders; no Docker clocks establish bare-metal Linux performance. Linux ARM64 qualification passes at the exact staged runtime commit: nine shared native gates,
four public builds,14processes/182calls and32refusal controls. Independent verification checks
all2,863staged seals, the official compiler binary, executable images and copied logs;2,846
tracked staged source files match that runtime commit. Docker architecture/network isolation
and successful container state are verified. Its clocks remain diagnostic only.


## Adjacent native block fall-through — retained (October 27)

Measured runtime `942879cef358d17bc0abbfe1ea613a0d165f6e72` against accepted charge-lowering
parent `741d935d02543ac151c18edeb7bc334200ccb6aa`, same Apple M1 Max and pinned checked
ARC/Clang ThinLTO build. A connected block may fall directly into the following physical
block's original gas/source guards. If its true arm is that successor, complement the verified
ARM condition and branch only to the other arm. Backedges and external destinations keep
explicit relocations; guards and state publication are unchanged. No synthetic work or native
operation is omitted from accounting.

An ignored source snapshot confirms the actual initialization graph:25351→25362→25373→25351
for internal edges, with distinct external exits25355/25365/25377. Source PCs are193987,
193996,194002. This removes two unconditional transfers per complete round, not its checks.
Snapshot hashes and four complete DOOM calls are retained; diagnostic clocks are discarded.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.461 / 3.781 | 2.800 / 2.993 | 2.788 / 2.892 | 2.838 / 2.808 | 5.979 / 6.088 | 0.805 / 0.765 | 0.466 / 0.475 |
| minimal 100000 | 4.880 / 4.968 | 4.879 / 5.108 | 4.891 / 5.043 | 4.880 / 5.051 | 6.125 / 6.197 | 1.002 / 1.015 | 0.799 / 0.814 |
| memset 100000 | 4.394 / 4.449 | 3.529 / 3.579 | 3.558 / 3.580 | 2.745 / 2.800 | 3.927 / 3.947 | 0.810 / 0.805 | 0.906 / 0.907 |
| pinky 1 | 85.406 / 86.210 | 72.070 / 72.834 | 72.136 / 72.873 | 72.905 / 73.755 | 94.384 / 94.755 | 0.845 / 0.845 | 0.764 / 0.769 |
| sieve 10000000 | 339.341 / 339.915 | 277.422 / 279.087 | 277.598 / 279.885 | 292.853 / 294.606 | 372.659 / 368.888 | 0.818 / 0.823 | 0.745 / 0.759 |
| init 0 | 328.108 / 322.579 | 221.948 / 220.738 | 218.982 / 218.048 | 221.908 / 217.929 | 674.405 / 674.176 | 0.667 / 0.676 | 0.325 / 0.323 |
| tick 0 | 40.569 / 40.722 | 37.697 / 37.650 | 37.515 / 37.356 | 34.117 / 33.971 | 45.651 / 44.366 | 0.925 / 0.917 | 0.822 / 0.842 |

Repeated public CPU ms: ten independent processes per role, five balanced ABBA blocks.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.810 (2.789–2.833) | 2.836 (2.809–2.881) | 1.009 | 1.019, 1.014, 1.004, 1.001, 1.017 |
| minimal 100000 | 4.852 (4.846–4.859) | 4.867 (4.843–4.886) | 1.003 | 1.007, 1.005, 1.002, 1.000, 1.000 |
| memset 100000 | 3.529 (3.490–3.606) | 3.538 (3.502–3.597) | 1.003 | 0.996, 1.014, 1.001, 0.998, 1.003 |
| pinky 1 | 72.584 (72.022–73.203) | 72.309 (71.861–72.768) | 0.996 | 0.998, 0.999, 0.994, 1.000, 0.987 |
| sieve 10000000 | 271.676 (271.219–273.423) | 271.274 (270.916–273.116) | 0.999 | 0.998, 0.998, 0.999, 0.997, 1.000 |
| init 0 | 221.898 (219.745–226.931) | 218.421 (215.832–219.781) | 0.984 | 0.987, 0.982, 0.982, 0.984, 0.966 |
| tick 0 | 37.486 (37.184–37.745) | 37.318 (37.024–37.630) | 0.996 | 0.997, 0.994, 1.001, 0.994, 0.994 |

The repeated public initialization median improves1.6%,221.898→218.421ms; all five balanced
blocks favor the candidate (ratios0.966–0.987). Process ranges nearly separate, overlapping
by0.036ms. This is a small local result supported by the explicit reduction in executed transfers,
not a claim of gains on another CPU. Short sieve's median increases0.9% with overlapping
ranges; long sieve is unchanged. Other medians differ by at most0.4% with overlapping ranges.
Retain the bounded layout improvement and record that short-workload tradeoff rather than
claiming a universal win. Native work/call counts remain identical; initialization code shrinks
83,044→83,036bytes. No hardware counters were collected or hardware cause inferred.

All nine native gates pass. Additional704literal cases cover all eight orientations of the three
branches, guards at each source/gas boundary, natural exit, register publication and visit counts.
The3,546region,486price/quota and1,024publication witnesses still pass. Kernel42/546/63/6/3
and application70/910/115/16/8 cohorts are independently reparsed with706/710seals, exact parent
sources and fresh equal-image controls. Extra140repeated processes/1,820calls independently
reparse with stable native counts across all14workload/role groups. Measured tracked bytes match
this preserving runtime commit (684kernel/667application files).

Constructor, cold, reused public call and retained-core reset/publication remain separate scopes;
reference DOOM invocation restoration/teardown remains separate from its raw call time. Linux
ARM64 qualification passes at this exact staged runtime: nine shared gates, four public builds,
14processes/182calls and32refusal controls. All2,863staged seals, official compiler bytes,
images and copied logs independently verify;2,846tracked staged files match the runtime commit.
Container architecture/network isolation and successful exit are verified; clocks are diagnostic only.
Raw local evidence lives in
`build/pvm-arm64-jit/region-layout/` and the sealed current kernel/application folders.


## Native visit counters in registers — retained (October 27)

Measured runtime `e0ba437d5e3059d90ab9824ff23cdf0e539ca333` against accepted layout parent
`ce512c8f5df7a2960eb2b6eb270c953fde98e085`, Apple M1 Max and the same pinned checked
ARC/Clang ThinLTO build. Connected native execution now keeps its three invocation-local visit
counters in caller-saved D16..D18, with the integer bit-pattern1 in D19. Scalar SIMD ADD performs
exact64-bit integer arithmetic: no floating-point arithmetic, conversion or precision assumption.
X17 remains the distinct general-purpose context pointer. No SP/LR/callee-saved register changes.

The five-word invocation context ABI is unchanged. Load the three fresh counters at entry,
perform one integer add per actual complete block, and store all three counters on every exit.
This replaces the previous per-block context load/add/store. Source/gas checks, debits, native
work accounting, guest-register publication and exact guard exits are unchanged. Nothing mutable
is retained in executable bytes. Admission, pricing and cache policy remain unchanged.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.481 / 3.415 | 2.819 / 2.757 | 2.781 / 2.787 | 2.843 / 2.789 | 5.990 / 5.893 | 0.799 / 0.816 | 0.464 / 0.473 |
| minimal 100000 | 4.947 / 4.888 | 4.900 / 4.887 | 4.910 / 4.870 | 4.900 / 4.875 | 6.018 / 5.997 | 0.993 / 0.996 | 0.816 / 0.812 |
| memset 100000 | 4.525 / 4.306 | 3.541 / 3.502 | 3.584 / 3.592 | 2.783 / 2.740 | 3.945 / 3.941 | 0.792 / 0.834 | 0.909 / 0.912 |
| pinky 1 | 85.493 / 85.426 | 72.487 / 72.216 | 73.109 / 72.254 | 73.510 / 75.124 | 94.645 / 94.325 | 0.855 / 0.846 | 0.772 / 0.766 |
| sieve 10000000 | 337.427 / 340.417 | 275.830 / 279.839 | 279.158 / 281.504 | 292.375 / 293.920 | 368.643 / 369.216 | 0.827 / 0.827 | 0.757 / 0.762 |
| init 0 | 324.509 / 320.159 | 219.960 / 220.596 | 213.172 / 210.482 | 213.367 / 209.916 | 675.063 / 677.171 | 0.657 / 0.657 | 0.316 / 0.311 |
| tick 0 | 39.814 / 39.739 | 37.499 / 37.114 | 37.294 / 36.933 | 33.657 / 33.380 | 44.307 / 44.358 | 0.937 / 0.929 | 0.842 / 0.833 |

Repeated public CPU ms: ten independent processes per role, five balanced ABBA blocks.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.888 (2.815–2.917) | 2.905 (2.892–2.919) | 1.006 | 1.005, 1.009, 1.016, 1.005, 1.003 |
| minimal 100000 | 5.045 (5.010–5.084) | 5.055 (4.893–5.074) | 1.002 | 1.001, 1.001, 0.991, 0.980, 1.003 |
| memset 100000 | 3.440 (3.396–3.618) | 3.448 (3.402–3.607) | 1.002 | 1.002, 0.998, 1.010, 1.001, 0.992 |
| pinky 1 | 71.700 (71.442–72.582) | 71.703 (71.474–72.112) | 1.000 | 1.003, 0.998, 1.000, 0.995, 0.999 |
| sieve 10000000 | 270.913 (270.522–273.101) | 270.553 (270.403–272.534) | 0.999 | 1.000, 0.997, 0.999, 0.996, 0.999 |
| init 0 | 215.092 (214.324–216.258) | 210.311 (209.330–211.255) | 0.978 | 0.977, 0.980, 0.974, 0.978, 0.976 |
| tick 0 | 37.109 (37.005–37.365) | 36.974 (36.734–37.482) | 0.996 | 1.002, 0.996, 0.992, 0.990, 1.001 |

Retain this isolated change: repeated public initialization improves2.2%,215.092→210.311ms.
All five balanced blocks improve2.0–2.6%, with non-overlapping process ranges. Short sieve's
median rises0.6% with overlapping ranges; other medians differ by at most0.4% and overlap.
The initial fill/long-sieve movements do not persist in repeated qualification. Native call/work
counts are identical. Initialization code grows83,036→83,044bytes: per-entry setup/publication
replaces repeated counter memory accesses. This is a measured local result, not a hardware
counter or microarchitectural-cause claim.

The host assembler independently confirms every new instruction encoding. Compile-only macOS
and Linux target controls confirm V16..V19 are caller-saved; the D8 positive control requires
stack preservation. A real executable-storage witness checks64pairs of literal integer values,
including2^53−1/2^53/2^53+1, the top bit, carries and unsigned wrap; all borrowed register/context
bytes outside its declared result remain unchanged. The strict terminal memory marker includes
`integer64`, so the shared qualifier requires completion of these new cases.

All nine shared native gates pass. Kernel42/546/63/6/3 and application70/910/115/16/8 cohorts
independently reparse with706/710sealed identities, exact accepted-parent source hashes and
fresh equal-image controls. Repeated140processes/1,820calls independently reparse with stable
native work in all14workload/role groups. Measured tracked sources match this runtime commit:
684kernel and667application files. Previous region/price/orientation/capacity witnesses pass.

Constructor, cold, reused public call and retained-core reset/publication remain separate;
reference DOOM restoration/teardown is separate from raw call CPU. Linux ARM64 qualification
passes at this exact staged runtime: nine shared gates, four public builds,14processes/182calls,
32refusal controls and the new64integer cases. Independent verification checks2,863staged seals,
2,846tracked source files bound to this commit, official compiler bytes, images and copied logs.
Container architecture/network isolation and successful exit verify; clocks remain diagnostic only.
Raw evidence, assembler/ABI controls and preserving
receipts live under `build/pvm-arm64-jit/resident-counters/` and sealed kernel/application folders.


## Scoped native adapter borrows — retained (October 27)

Measured runtime `3b8ecacc34d33d93f7f9dec36dcad6d73c2be6f4` against accepted counter parent
`70900fcdbb5cf7100e53ea3fc4397d54419ee33e`, Apple M1 Max, unchanged pinned checked
ARC/Clang ThinLTO. Only three native adapters change:flatArmRunNext,flatArmEnter,flatArmExecute.
Their temporary cache references are explicit scoped cursor borrows. The exclusive frame retains
the cache throughout a non-host native call; mutable register bytes are a disjoint sibling.
The header's borrow ends before the next helper receives the whole mutable frame. No borrow
bypass, ownership transfer, host callback or retained invocation pointer is introduced.

Nil assertions, typed failure paths, bounds checks, quota/gas ordering, partial barriers, source
PCs, native generation, metrics and cache admission remain unchanged. Generated C independently
confirms all refcount work disappears in these three functions:baseline8/5/8refcount mentions,
current0/0/0. Function extraction and complete generated-source hashes are retained. The native
register/branch instruction generator is unchanged; native call/work counts and emitted lengths
remain identical for every workload.

A separate12process/156checked-call sampling cohort on sealed pre-trial images identified
427/761long-sieve leaf samples in flatArmEnter. Disassembly confirms repeated ownership guards,
arena validation and count-array metadata work. Those samples guide the bounded hypothesis;
they do not prove that ARC alone caused that share. Sample clocks are discarded. Profiles for
public interpreter/JIT, retained core and reference across long sieve and both DOOM phases,
all snapshot hashes and full-state outputs independently verify against710sealed identities.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.463 / 3.421 | 2.801 / 2.767 | 2.764 / 2.736 | 2.522 / 2.497 | 5.941 / 5.923 | 0.798 / 0.800 | 0.465 / 0.462 |
| minimal 100000 | 4.931 / 4.894 | 4.946 / 4.869 | 4.941 / 4.880 | 4.902 / 4.841 | 6.019 / 5.994 | 1.002 / 0.997 | 0.821 / 0.814 |
| memset 100000 | 4.367 / 4.377 | 3.447 / 3.511 | 3.400 / 3.414 | 2.671 / 2.693 | 3.954 / 4.030 | 0.778 / 0.780 | 0.860 / 0.847 |
| pinky 1 | 85.403 / 85.947 | 72.243 / 72.934 | 72.151 / 72.428 | 71.038 / 71.909 | 94.302 / 95.228 | 0.845 / 0.843 | 0.765 / 0.761 |
| sieve 10000000 | 336.276 / 347.659 | 275.817 / 283.831 | 269.378 / 275.219 | 264.123 / 268.978 | 366.474 / 372.920 | 0.801 / 0.792 | 0.735 / 0.738 |
| init 0 | 319.166 / 321.637 | 209.396 / 209.833 | 211.494 / 209.441 | 209.851 / 208.482 | 674.716 / 690.492 | 0.663 / 0.651 | 0.313 / 0.303 |
| tick 0 | 40.205 / 39.977 | 37.238 / 37.171 | 36.709 / 36.424 | 33.283 / 33.029 | 43.928 / 44.234 | 0.913 / 0.911 | 0.836 / 0.823 |

Repeated public CPU ms: ten independent processes per role, five balanced ABBA blocks.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.803 (2.774–2.820) | 2.768 (2.748–2.856) | 0.988 | 0.988, 0.983, 0.985, 0.987, 1.007 |
| minimal 100000 | 4.911 (4.871–5.021) | 4.933 (4.893–5.026) | 1.004 | 0.997, 1.013, 1.005, 1.004, 1.005 |
| memset 100000 | 3.475 (3.429–3.521) | 3.359 (3.344–3.398) | 0.967 | 0.978, 0.959, 0.971, 0.966, 0.966 |
| pinky 1 | 72.108 (71.900–72.553) | 71.908 (71.609–73.375) | 0.997 | 0.999, 0.993, 0.997, 1.009, 0.995 |
| sieve 10000000 | 270.748 (270.642–272.443) | 266.558 (266.343–268.199) | 0.985 | 0.983, 0.985, 0.985, 0.984, 0.985 |
| init 0 | 209.857 (209.107–210.561) | 209.846 (208.797–210.428) | 1.000 | 1.001, 0.998, 1.001, 1.000, 0.999 |
| tick 0 | 37.161 (36.869–37.356) | 36.669 (36.480–37.337) | 0.987 | 0.987, 0.990, 0.984, 0.987, 0.996 |

Retain the public-call improvement:fill3.3% and long sieve1.5%, with non-overlapping process
ranges and all five balanced blocks favoring the candidate. Gameplay improves1.3% in its median
and all five blocks favor it, though process ranges overlap. Short sieve1.2%/Pinky0.3% movements
have overlapping ranges; no smaller broad win is claimed. Minimal's median rises0.4% with
substantial overlap; initialization is unchanged. Retained-core sieve's earlier~9% result is
not the public speedup and must not be substituted for it.

All nine native/opcode/host/exclusive-owner gates and ARC1000pass. Kernel42processes/546calls/
63controls/6freshbuilds/3equal-image pairs and public70/910/115/16/8cohorts independently reparse
with706/710seals and exact accepted-parent sources. Another140public processes/1,820calls
independently reparse with stable native counters in14workload/role groups. Measured tracked
bytes match this runtime commit:684kernel and667application files.

Constructor, cold, reused public call and core reset/publication scopes remain separate;
reference restoration/teardown remains separate from its call CPU. Linux qualification passes
at the exact staged runtime:nine shared gates,four public builds,14processes/182calls and
32refusal controls. All2,863staged seals,2,846tracked files bound to this commit, official compiler
bytes, images and copied logs independently verify; Docker architecture/network isolation and
successful exit pass. Its clocks remain diagnostic only. Records:`build/pvm-arm64-jit/adapter-borrows/`, pre-trial samples
in`accepted-sampling/`, and the sealed current kernel/application folders. No defaults/CI/pins
change; no hardware counter or microarchitectural-cause claim is made.


## Scalar native entry records — retained (October 27)

Measured runtime `51368a6925949f5daa358d087e37c1258f6645b2` against accepted borrow parent
`e4eebf0e406a1957b8d4d99e2a2999f9c03a7257`, same Apple M1 Max and pinned checked
ARC/Clang ThinLTO. Replace three private parallel code/count/successor arrays with one sequence
of12-byte scalar records:code,operation count,successor. Hot code/count fields are adjacent;
the native caller deliberately copies a small plain value before calling non-host native code.
No record reference spans a possible sequence reallocation. The frame retains its cache owner.

All fields commit together only after successful executable publication; a failed replacement
preserves the prior complete tuple. A new witness proposes successor99999/count123 after filling
the arena and verifies the old successor77/count1 remains callable. Fresh refusal/default records
remain0/1coded. The map still has262,144coordinates; publication ceilings and one-MiB arena are
unchanged. Native generation, instruction words, ABI, gas/source checks, memory/hosts and metrics
are unchanged. The constructor checks the natural record size is exactly12bytes.

Generated C independently confirms metadata index paths drop3→1for arithmetic and2→1for
conditional entries; regions remain1→1. There are no record refcount/copy hooks. Complete before/
after functions and generated-file hashes are retained. This supports the chosen mechanism,
not a claim about hardware misses or all CPU causes. An initial inspection assumed identical
module filename hashes across kernel/DOOM namespaces; correcting that discovery completed the
proof. No compile/runtime failure occurred.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.571 / 3.514 | 2.719 / 2.800 | 2.631 / 2.708 | 2.530 / 2.522 | 5.894 / 6.071 | 0.737 / 0.771 | 0.446 / 0.446 |
| minimal 100000 | 4.885 / 4.991 | 4.896 / 4.972 | 4.899 / 4.970 | 4.845 / 5.002 | 5.993 / 6.169 | 1.003 / 0.996 | 0.817 / 0.806 |
| memset 100000 | 4.330 / 4.468 | 3.312 / 3.446 | 3.352 / 3.481 | 2.654 / 2.721 | 4.032 / 4.040 | 0.774 / 0.779 | 0.831 / 0.862 |
| pinky 1 | 85.522 / 86.522 | 71.745 / 73.327 | 70.955 / 71.604 | 71.022 / 73.343 | 93.976 / 96.010 | 0.830 / 0.828 | 0.755 / 0.746 |
| sieve 10000000 | 336.062 / 340.447 | 269.870 / 269.819 | 259.345 / 266.940 | 258.175 / 263.404 | 366.616 / 374.945 | 0.772 / 0.784 | 0.707 / 0.712 |
| init 0 | 319.409 / 328.687 | 210.411 / 210.474 | 209.206 / 212.071 | 208.643 / 209.946 | 684.864 / 675.136 | 0.655 / 0.645 | 0.305 / 0.314 |
| tick 0 | 40.702 / 39.935 | 37.553 / 36.923 | 37.465 / 36.783 | 35.079 / 34.264 | 44.977 / 44.261 | 0.920 / 0.921 | 0.833 / 0.831 |

Repeated public CPU ms: ten independent processes per role, five balanced ABBA blocks.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.747 (2.728–2.760) | 2.652 (2.643–2.672) | 0.966 | 0.966, 0.965, 0.968, 0.971, 0.962 |
| minimal 100000 | 4.917 (4.848–4.960) | 4.908 (4.864–4.925) | 0.998 | 0.991, 1.003, 0.995, 0.999, 1.003 |
| memset 100000 | 3.362 (3.329–3.418) | 3.396 (3.350–3.496) | 1.010 | 1.008, 1.003, 1.027, 1.025, 1.006 |
| pinky 1 | 71.720 (71.611–72.259) | 70.865 (70.468–71.394) | 0.988 | 0.983, 0.989, 0.988, 0.992, 0.985 |
| sieve 10000000 | 266.490 (265.909–268.267) | 257.151 (256.890–259.355) | 0.965 | 0.963, 0.972, 0.966, 0.966, 0.964 |
| init 0 | 210.366 (208.826–214.093) | 210.865 (209.572–211.717) | 1.002 | 1.003, 1.006, 1.001, 0.992, 1.006 |
| tick 0 | 36.763 (36.495–37.026) | 36.638 (36.471–37.754) | 0.997 | 0.989, 1.001, 0.998, 1.014, 0.994 |

Retain:repeated public sieve100k improves3.4%,long sieve3.5%,Pinky1.2%; all five balanced
blocks favor each and process ranges do not overlap. Memory fill costs1.0% with overlapping
ranges (all five block medians favor the parent); this is a recorded small tradeoff, not a
universal gain. Other workload medians differ by at most0.3% and overlap. Native work/call
counts and emitted lengths remain identical. No hardware counters were collected.

All nine native/opcode/host/exclusive-owner gates and prior region/price/orientation/capacity
witnesses pass. Kernel42/546/63/6/3 and application70/910/115/16/8cohorts independently reparse
with706/710sealed identities, exact accepted-parent sources and fresh equal-image controls.
Repeated140processes/1,820calls independently reparse with stable native counters in14groups.
Measured tracked sources match this runtime commit:684kernel and667application files.

Constructor,cold,reused public and core reset/publication scopes remain separate; reference
DOOM lifecycle remains separate from raw call CPU. Linux qualification passes at this exact
staged runtime:nine shared gates,four public builds,14processes/182calls and32refusal controls.
All2,863staged seals,2,846tracked files bound to this commit, official compiler bytes, images
and copied logs independently verify. Docker architecture/network isolation and successful exit
pass; its clocks remain diagnostic only. Raw receipts, lowering proof and distributions:`build/pvm-arm64-jit/entry-records/`
and sealed current kernel/application folders. No defaults,CLI,CI or pins change.


## Master maintenance reconciliation (October 27)

Normal merge of master `1a768c26879c14965e4e37bf2ee9ce89bcbb1abd` is recorded at
`37661556abc39532c7e977971ac0c8267cbb1b2d`. Exact Git object identities prove the complete
runtime tree,native bridge,four benchmark drivers and toolchain file are unchanged from the
qualified record layout. Top-level parser helper ASTs are identical; master changes affect CI,
maintenance tooling and documentation. No dependency upgrade or JIT CI job is introduced.

Full Python discovery ran1,552tests in1,459.618seconds:one failure,two skips. The failed release
matrix safeguard already existed before reconciliation:it equated all available compiler archives
with the two qualified CI binary-release hosts. The draft's same-version Linux ARM64 compiler
pin is for local qualification and does not automatically add a qualified release runner. The fix
retains exact Linux/macOS release-platform assertions and validates each selected platform's
pinned OS/architecture; it permits additional available compiler platforms. No workflow expands.
All50focused Nimony/CI safeguards pass after this fix. The full failed receipt remains retained;
a new complete green discovery is not claimed here. Final qualification may rerun discovery after
the remaining runtime experiment; unchanged tests need not be duplicated while iterating.

Evidence:`build/pvm-arm64-jit/master-reconciliation/identity.json`,full failed Python logs/report
and focused`nimony-ci.log`. Previously qualified runtime measurements remain tied to their
preserved exact heads; forthcoming comparisons use the reconciled source/tooling cohort.

## Rejected publication-sealed entries

Measured prototype `5297454368aedb33411246eef1fd230c16913d9a` against maintenance-reconciled accepted parent `be50dad1567d87bf81684924f8db5cc3348ad5a0`. A private fixed arena-base borrow and cold owner/range/alignment seal moved immutable offset validation out of native calls. Records remained12 bytes; code, counters, guest checks and source/budget semantics were unchanged. The raw C/Nim prototype and controls remain in that commit.

Repeated public CPU ms: ten independent processes per role, five balanced ABBA blocks.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.643 (2.626–2.693) | 2.649 (2.639–2.689) | 1.003 | 1.014, 1.002, 0.992, 1.004, 0.995 |
| minimal 100000 | 4.928 (4.862–5.032) | 4.964 (4.901–5.061) | 1.007 | 1.000, 1.000, 1.019, 1.003, 1.014 |
| memset 100000 | 3.382 (3.361–3.538) | 3.319 (3.293–3.791) | 0.981 | 0.960, 0.996, 1.034, 0.980, 0.960 |
| pinky 1 | 70.209 (69.883–71.133) | 70.036 (69.830–70.785) | 0.998 | 1.000, 0.998, 1.000, 0.995, 0.999 |
| sieve 10000000 | 258.569 (256.775–259.290) | 257.302 (256.627–262.444) | 0.995 | 0.999, 0.995, 1.004, 1.003, 1.001 |
| init 0 | 211.277 (209.260–217.561) | 211.694 (210.000–214.431) | 1.002 | 0.996, 1.006, 1.007, 0.990, 0.999 |
| tick 0 | 36.788 (36.556–37.340) | 36.543 (36.424–36.697) | 0.993 | 0.991, 0.997, 0.994, 0.997, 0.986 |

Verdict:reject and restore the five isolated runtime/control/helper files byte-for-byte from the accepted parent. Public sieve/Pinky are effectively flat; fill's1.9% median improvement is inconsistent across balanced blocks and overlaps substantially; gameplay improves0.7% with overlapping ranges. Retained-core sieve regresses3.2% in both orders. This does not justify expanding the private entry/lifetime machinery. Counts alone do not identify a CPU cause. All seven workload groups have identical native operation/call/length counts across both versions.

Mac correctness:all nine native gates,1,000 executable-storage lifetimes and new owner/base/alignment/append/full-arena controls passed. Kernel42processes/546calls/63controls/6fresh builds/3equal-image pairs; public70/910/115/16/8; another140balanced public processes/1,820calls. Independent706/710sealed identities, raw logs, exact parent sources and preserving-commit proofs684/667tracked files passed. No Linux run was requested for this rejected implementation; the retained parent already has Linux qualification. Ignored evidence:`build/pvm-arm64-jit/sealed-entry-capabilities/`.

## Complete native block accounting

Measured runtime `efece20b92d915915211a710aeb672041510f5f9` against accepted parent `087c018850d5d58ac9ce481af71f295b5d4d1593`. Only an already sealed complete pure arithmetic/conditional suffix receives the private whole-block entry. Full unpaid calls debit the same gas/span and retain the exact reservation endpoint, without the transient paid=true/paid=false pair. Partial budgets, already-paid resumes, insufficient gas and active barriers call the original entry. Native code cannot observe the omitted flag writes because it has no host, memory fault or genuine exit inside this complete suffix. The shared static call helper retains the old result/error/bounds checks. No pricing/cache/ISA/ownership/default/CI change.

Repeated public CPU ms: ten independent processes per role, five balanced ABBA blocks.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.668 (2.638–2.711) | 2.596 (2.543–2.655) | 0.973 | 0.968, 0.962, 0.995, 0.968, 0.958 |
| minimal 100000 | 4.953 (4.931–4.975) | 4.973 (4.924–5.011) | 1.004 | 1.008, 0.995, 1.005, 1.005, 1.006 |
| memset 100000 | 3.409 (3.380–3.512) | 3.414 (3.380–3.453) | 1.002 | 1.001, 0.992, 0.999, 0.999, 1.000 |
| pinky 1 | 71.616 (71.320–72.479) | 71.209 (70.794–71.856) | 0.994 | 0.991, 0.994, 0.995, 0.993, 0.991 |
| sieve 10000000 | 257.567 (256.666–266.854) | 247.757 (247.131–257.899) | 0.962 | 0.969, 0.962, 0.964, 0.948, 0.962 |
| init 0 | 210.221 (209.536–215.244) | 209.856 (209.164–213.938) | 0.998 | 0.997, 0.992, 0.996, 0.998, 1.000 |
| tick 0 | 36.826 (36.627–37.142) | 37.420 (37.336–37.636) | 1.016 | 1.015, 1.019, 1.014, 1.025, 1.014 |

Retain the measured tradeoff:short sieve2.7% and long sieve3.8% faster, all five balanced block medians favoring each. Short-sieve process ranges overlap; long-sieve ranges overlap slightly at their tails but every balanced block favors the trial. Pinky0.6% faster with overlap. Gameplay is consistently1.6% slower, with non-overlapping process ranges; this is a real small cost, not a no-regression claim. Minimal/fill/init differ by at most0.4% with overlapping ranges. Native operations/calls/branches/headers/lengths are identical in all seven groups across versions. Counts do not establish the CPU cause of either change.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.416 / 3.414 | 2.628 / 2.755 | 2.603 / 2.635 | 2.421 / 2.429 | 5.896 / 5.918 | 0.762 / 0.772 | 0.441 / 0.445 |
| minimal 100000 | 4.885 / 4.902 | 4.870 / 4.868 | 4.991 / 4.893 | 4.925 / 4.854 | 6.001 / 5.997 | 1.022 / 0.998 | 0.832 / 0.816 |
| memset 100000 | 4.309 / 4.322 | 3.348 / 3.344 | 3.339 / 3.340 | 2.646 / 2.738 | 3.939 / 3.928 | 0.775 / 0.773 | 0.848 / 0.850 |
| pinky 1 | 84.483 / 84.933 | 70.207 / 70.287 | 70.342 / 69.710 | 70.621 / 69.912 | 94.139 / 93.426 | 0.833 / 0.821 | 0.747 / 0.746 |
| sieve 10000000 | 336.207 / 339.277 | 257.205 / 259.076 | 249.774 / 254.299 | 254.881 / 253.643 | 366.704 / 366.861 | 0.743 / 0.750 | 0.681 / 0.693 |
| init 0 | 319.425 / 319.753 | 211.788 / 209.957 | 209.402 / 209.231 | 208.567 / 209.499 | 675.041 / 672.826 | 0.656 / 0.654 | 0.310 / 0.311 |
| tick 0 | 40.222 / 39.632 | 36.794 / 36.643 | 37.246 / 37.411 | 34.046 / 33.969 | 44.212 / 44.111 | 0.926 / 0.944 | 0.842 / 0.848 |

All9Mac native gates pass, including10,560 warm-cache paid/gas/source/pricing cases and full host/CPU/gas/page/permission/source checks. Kernel42processes/546calls/63controls/6freshbuilds/3equal-image pairs; public70/910/115/16/8; another140balanced processes/1,820calls. Independent706/710seals, exact parent sources, raw receipts and preserving runtime proofs684/667tracked files pass. An ignored source snapshot with a deliberate assertion immediately inside the admitted complete path fails at exactly ARM_WHOLE_PATH_REACHED under the same witness; this proves the path executes, while its clocks are discarded. Production has no trace/assertion hook.

Linux ARM64 also passes9shared gates,4public builds,14processes/182calls/32refusal controls,2,863sealed identities and2,846tracked source files bound to measured runtime `efece20b92d915915211a710aeb672041510f5f9`. Official pinned compiler binary, image/architecture/network isolation and copied raw logs/states verify independently. Docker timings are diagnostic only. No hardware counters were collected. Evidence:`build/pvm-arm64-jit/whole-native-header/`, including the explicit gameplay tradeoff.

## Regional arithmetic constants

Measured runtime `3a60bd09fdc4439ca813f8cb5d0ee33a9de88829`, accepted parent `397dc77b1213a61d3d2a0445cb18d88775a4d31f`.

The private regional-body factory selects MOVZ/MOVN plus only differing MOVK halfwords for arithmetic constants. Ordinary fragment words, conditional compare/return sequences and wide-price materialization retain their previous policy. This revisits previously rejected ordinary-fragment shortening only in the newer connected execution model. No guest memory, host, gas/source, cache bound, ownership, ABI or default changes.

Retain:initialization209.934→199.302ms(5.1%) and gameplay37.688→36.479ms(3.2%), all five balanced blocks favoring the trial with non-overlapping ranges. Long sieve improves0.8%, likewise non-overlapping/all five blocks. Minimal costs0.4% consistently with non-overlapping ranges; this small tradeoff is explicit. Short sieve/fill/Pinky overlap and differ by at most0.5%. Gameplay and sieve execute no connected region, so their improvements cannot be attributed to executing shorter regional constants:these are observed whole-image code-generation/layout side effects, with no hardware cause established.

Native operations/calls/branches/headers match exactly in all seven workload groups. Only initialization code length changes,83,044→82,996bytes; ordinary code lengths are identical. Separate exact-source diagnostics pass eight complete checked DOOM calls with all clocks discarded. They show unchanged guarded visits and body reductions3/3/6words. Across two initialization calls, observed block visits42,608,063/42,589,999/42,589,999 account for511,134,180fewer unconditional body instructions. This is derived code-length×visit accounting, not hardware counters. The first diagnostic had a directory/binary naming collision; its originating linker receipt is retained, and only that diagnostic was rerun with distinct names. Production/timing cohorts were unaffected.

All9Mac native gates pass, including1,209literal constant cases in each ordinary/regional policy(all13destinations, zero/ones/high/mixed patterns). Kernel42processes/546calls/63controls/6freshbuilds/3equal-image pairs; applications70/910/115/16/8;140balanced public processes/1,820calls. Independent706/710seals, exact parent objects, raw logs, native quantities and preserving commit proofs684/667tracked files pass. Both diagnostic snapshots bind477original source files to their respective measured cohort; only the declared two instrumentation modules and diagnostic driver differ.

LinuxARM64:9shared gates,4public builds,14processes/182calls,32controls,2,863sealed files/2,846tracked source files bound to this runtime. Official compiler archive/binary, private build caches, image/architecture/network isolation and copied protocols verify. Container clocks remain diagnostic only. Full public cold CPU includes preparation/publication, including regional body emission; the supplementary compilation counter's regional bracket will be widened separately. No hardware counters were collected. Evidence:`build/pvm-arm64-jit/region-constants/`.

Repeated public CPU ms: ten independent processes per role, five balanced ABBA blocks.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.537 (2.513–2.631) | 2.524 (2.510–2.532) | 0.995 | 0.994, 0.996, 0.996, 1.003, 0.976 |
| minimal 100000 | 4.838 (4.823–4.847) | 4.859 (4.853–4.877) | 1.004 | 1.004, 1.007, 1.006, 1.004, 1.004 |
| memset 100000 | 3.334 (3.303–3.352) | 3.327 (3.313–3.334) | 0.998 | 1.000, 0.994, 0.996, 1.006, 0.997 |
| pinky 1 | 69.655 (69.409–70.525) | 69.654 (69.463–69.790) | 1.000 | 1.000, 1.000, 0.999, 0.995, 1.001 |
| sieve 10000000 | 247.347 (247.083–247.607) | 245.314 (244.984–245.946) | 0.992 | 0.992, 0.992, 0.992, 0.993, 0.991 |
| init 0 | 209.934 (209.635–211.520) | 199.302 (198.919–200.940) | 0.949 | 0.951, 0.948, 0.946, 0.950, 0.950 |
| tick 0 | 37.688 (37.441–37.969) | 36.479 (36.196–36.615) | 0.968 | 0.957, 0.966, 0.973, 0.963, 0.972 |

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.450 / 3.421 | 2.550 / 2.541 | 2.543 / 2.514 | 2.369 / 2.357 | 5.944 / 5.902 | 0.737 / 0.735 | 0.428 / 0.426 |
| minimal 100000 | 4.950 / 4.880 | 4.980 / 4.880 | 4.960 / 4.888 | 4.917 / 4.965 | 6.160 / 6.013 | 1.002 / 1.002 | 0.805 / 0.813 |
| memset 100000 | 4.543 / 4.311 | 3.491 / 3.334 | 3.501 / 3.346 | 2.645 / 2.651 | 3.929 / 3.920 | 0.771 / 0.776 | 0.891 / 0.854 |
| pinky 1 | 84.746 / 84.728 | 69.490 / 69.992 | 69.469 / 69.865 | 70.032 / 70.236 | 93.524 / 93.713 | 0.820 / 0.825 | 0.743 / 0.746 |
| sieve 10000000 | 336.373 / 336.214 | 250.364 / 247.367 | 245.734 / 245.774 | 244.514 / 244.732 | 366.361 / 368.180 | 0.731 / 0.731 | 0.671 / 0.668 |
| init 0 | 319.625 / 324.834 | 210.494 / 213.559 | 202.367 / 202.542 | 198.835 / 202.209 | 672.460 / 671.880 | 0.633 / 0.624 | 0.301 / 0.301 |
| tick 0 | 39.841 / 40.752 | 37.681 / 38.259 | 36.300 / 37.114 | 34.172 / 34.776 | 44.525 / 44.873 | 0.911 / 0.911 | 0.815 / 0.827 |

## Regional comparison constants

Measured runtime `d11d785f7f1bf03960ea651ec9647331d00e5afe`, accepted parent `aab4f68dcd242c5967c9f3b4c51fbf5e686248ea`.

The regional policy now shortens conditional comparison operands as well as arithmetic constants. Ordinary branch code, the final five return-selector words, wide-price guards, ABI and caps remain unchanged. The private regional factory alone admits shortened7–9word terminal shapes alongside original6/10word shapes; the compiler still copies exactly the compare prefix, extracts the unchanged final condition and relocates every guarded edge after emission.

Retain:initialization199.561→194.301ms(2.6%), all five balanced blocks favoring the trial with non-overlapping ranges. Other workloads differ by at most1.0% with overlapping ranges. Pinky costs0.5%; gameplay improves1.0%, with one balanced block favoring the parent. Neither executes a connected region, so these small changes are whole-image code-generation/layout effects, not evidence of regional instruction execution there. No CPU cause is inferred from code lengths.

Both ordinary and regional branch policies pass3,136independent predicate/register-preservation cases each; both constant policies retain1,209literal cases each. Direct price486and orientation704fixtures now exercise compact comparison prefixes; the capacity fixture retains full prefixes. All9Mac native/opcode/host/lifetime/owner gates pass. Kernel42processes/546calls/63controls/6freshbuilds/3equal-image pairs; public70/910/115/16/8;140balanced processes/1,820calls. Independent706/710source/input/compiler/image seals, exact parent sources, raw receipts and preserving-commit proofs684/667tracked files pass.

Native operations/calls/branches/headers match across versions; only initialization code length changes82,996→82,972bytes. Eight separate complete checked DOOM calls, with diagnostic clocks discarded, confirm unchanged guarded visits and compare-prefix reductions3/3/0instructions. Observed visits42,608,063/42,589,999/42,589,999across two initialization calls account for255,594,186fewer unconditional compare-prefix instructions. This derives from code lengths×visits, not hardware counters. Both477-file diagnostic originals match the measured source cohorts.

LinuxARM64 passes9shared gates,4public builds,14processes/182calls,32controls,2,863sealed identities/2,846tracked files bound to this measured runtime. Official compiler binary/archive, copied raw protocols and image/architecture/network identities independently verify; container clocks remain diagnostic only. No guest-memory, host, source/gas, ownership, default, dependency or JIT CI change. Full constructor/cold/reused/lifecycle scopes remain separate. Evidence:`build/pvm-arm64-jit/region-compare-constants/`.

Repeated public CPU ms: ten independent processes per role, five balanced ABBA blocks.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.531 (2.514–2.622) | 2.526 (2.519–2.546) | 0.998 | 1.007, 0.999, 1.000, 1.001, 0.977 |
| minimal 100000 | 4.866 (4.848–4.915) | 4.866 (4.849–4.971) | 1.000 | 0.997, 0.998, 1.005, 1.002, 1.006 |
| memset 100000 | 3.351 (3.333–3.386) | 3.351 (3.324–3.374) | 1.000 | 0.993, 0.998, 0.995, 1.003, 1.002 |
| pinky 1 | 69.710 (69.419–70.031) | 70.034 (69.497–70.579) | 1.005 | 1.006, 1.007, 1.001, 1.000, 1.005 |
| sieve 10000000 | 246.047 (245.558–248.791) | 245.809 (245.256–247.856) | 0.999 | 0.999, 0.995, 0.999, 1.003, 0.998 |
| init 0 | 199.561 (198.974–200.242) | 194.301 (193.752–196.109) | 0.974 | 0.972, 0.978, 0.972, 0.976, 0.974 |
| tick 0 | 36.717 (36.471–37.331) | 36.352 (36.291–36.828) | 0.990 | 1.001, 0.989, 0.995, 0.985, 0.984 |

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.480 / 3.415 | 2.530 / 2.522 | 2.561 / 2.503 | 2.396 / 2.354 | 6.032 / 5.854 | 0.736 / 0.733 | 0.425 / 0.428 |
| minimal 100000 | 4.947 / 4.878 | 4.962 / 4.923 | 4.968 / 4.876 | 4.955 / 4.874 | 6.101 / 5.998 | 1.004 / 1.000 | 0.814 / 0.813 |
| memset 100000 | 4.429 / 4.344 | 3.546 / 3.310 | 3.485 / 3.325 | 2.692 / 2.667 | 3.986 / 3.933 | 0.787 / 0.765 | 0.874 / 0.845 |
| pinky 1 | 86.609 / 84.584 | 71.672 / 69.507 | 71.718 / 69.760 | 72.322 / 70.207 | 93.701 / 93.489 | 0.828 / 0.825 | 0.765 / 0.746 |
| sieve 10000000 | 339.213 / 336.276 | 245.631 / 245.684 | 245.745 / 245.502 | 244.756 / 244.702 | 366.863 / 366.678 | 0.724 / 0.730 | 0.670 / 0.670 |
| init 0 | 319.861 / 319.858 | 199.262 / 200.095 | 194.340 / 194.539 | 193.438 / 193.755 | 671.861 / 671.513 | 0.608 / 0.608 | 0.289 / 0.290 |
| tick 0 | 40.113 / 40.404 | 36.360 / 36.613 | 36.756 / 36.245 | 34.275 / 34.423 | 44.538 / 44.813 | 0.916 / 0.897 | 0.825 / 0.809 |

## Qualified autonomous ARM64 JIT session

Public runtime434270d13d0a3efef57f429c9fa0aedfc56ce119 versus session start01f9c6742e18cb87b97545417c85a734dddf3350, Apple M1 Max, pinned October26Nimony358b9bce4dd855453f57a80a0c499b0b2e27d7ee, checked ARC release/Clang ThinLTO. Later tooling63eeaa3c04e9f3471306c8ffd51b9e6a6877b6c6 has identical runtime/header/driver/toolchain objects and identical public parser/revision APIs. Only kernel diagnostic flags were normalized afterward. Measured source provenance remains attached to434270d1, independently bound across667tracked files.

CPU ms, forward / reverse. Reused complete public PreparedProgram calls.

| Workload | Ours interpreted | Ours JIT | PolkaVM interpreted | JIT / reference |
|---|---:|---:|---:|---:|
| Sieve100k | 3.391 / 3.400 | 2.595 / 2.538 | 6.091 / 5.873 | 0.426 / 0.432 |
| Minimal100k | 4.964 / 4.872 | 4.902 / 4.910 | 6.024 / 6.024 | 0.814 / 0.815 |
| Memory fill100k | 4.454 / 4.322 | 3.325 / 3.314 | 3.909 / 3.925 | 0.851 / 0.845 |
| Pinky | 84.705 / 84.468 | 70.234 / 69.472 | 93.543 / 94.204 | 0.751 / 0.737 |
| Sieve10m | 332.930 / 333.580 | 247.456 / 248.380 | 367.651 / 366.829 | 0.673 / 0.677 |
| DOOM initialization | 320.086 / 319.064 | 194.958 / 195.561 | 678.008 / 677.702 | 0.288 / 0.289 |
| DOOM gameplay | 40.064 / 41.193 | 36.794 / 37.320 | 43.941 / 43.941 | 0.837 / 0.849 |


Our table uses complete reusable PreparedProgram calls with fresh invocation memory and immutable publication; reference raw-call clocks exclude its restoration/teardown. Samples3–12 determine each process median; forward/reverse orders remain separate. No hardware counters.

### Balanced session-start pairing

Repeated public CPU ms: ten independent processes per role, five balanced ABBA blocks.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.777 (2.767–2.890) | 2.547 (2.525–2.616) | 0.917 | 0.919, 0.907, 0.910, 0.920, 0.924 |
| minimal 100000 | 4.873 (4.838–4.998) | 4.884 (4.856–5.595) | 1.002 | 0.997, 1.079, 1.002, 0.999, 1.005 |
| memset 100000 | 3.436 (3.418–3.463) | 3.337 (3.315–3.411) | 0.971 | 0.969, 0.976, 0.981, 0.963, 0.970 |
| pinky 1 | 71.688 (71.436–71.818) | 69.771 (69.591–69.891) | 0.973 | 0.972, 0.974, 0.975, 0.971, 0.973 |
| sieve 10000000 | 271.360 (270.809–275.764) | 247.657 (247.087–248.236) | 0.913 | 0.913, 0.913, 0.913, 0.905, 0.912 |
| init 0 | 226.821 (226.291–229.150) | 195.234 (194.223–198.987) | 0.861 | 0.858, 0.865, 0.858, 0.862, 0.864 |
| tick 0 | 37.487 (36.962–37.845) | 36.654 (36.274–37.451) | 0.978 | 0.978, 0.980, 0.984, 0.974, 0.991 |


Retain the observed aggregate gains:initialization13.9%,long sieve8.7%,short sieve8.3%,fill2.9%,Pinky2.7%, with all five balanced blocks favoring each. Gameplay2.2% overlaps process ranges but all five block medians favor the result. Minimal has overlapping ranges and an untrimmed candidate outlier; no useful gain is claimed. This is a separate repeated-process cohort using reused samples1–12; do not mix its absolute medians into the forward/reverse pairing.

### Construction, cold calls and reference lifecycle

Our prepared-owner constructor is outside its call clock and shown separately. The cold call is sample0 and includes all lazy code emission/publication. Reference module construction is outside these clocks and was not measured by this cohort; its cold raw call is not a full reference startup cost.

| Workload | Our prepared owner | Our cold public call | Reference cold raw call |
|---|---:|---:|---:|
| Sieve100k | 1.642 / 1.606 | 7.799 / 7.504 | 6.303 / 6.164 |
| Minimal100k | 0.013 / 0.010 | 4.966 / 5.060 | 6.017 / 6.032 |
| Memory fill100k | 0.049 / 0.051 | 5.155 / 4.708 | 3.996 / 3.956 |
| Pinky | 0.458 / 0.457 | 73.482 / 72.320 | 93.436 / 94.208 |
| Sieve10m | 1.650 / 1.601 | 252.231 / 253.589 | 366.692 / 366.934 |
| DOOM initialization | 7.679 / 7.609 | 214.549 / 212.832 | 675.199 / 680.235 |
| DOOM gameplay | 7.880 / 7.574 | 48.261 / 47.030 | 44.256 / 43.950 |

Short sieve is a clear startup tradeoff:the cold public call is about7.8ms before its owner-construction cost, versus about6.3ms for the reference raw call. Warm wins do not imply universal cold/startup wins. Production caller-lifetime integration/default activation remains a separate decision.

CPU ms, forward / reverse; each component median is independent, so displayed component medians need not sum exactly to the median total. Each of the13underlying records satisfies restoration+call+teardown=total and matches its paired raw call clock.

| Phase | Restoration | Raw call | Teardown | Full invocation |
|---|---:|---:|---:|---:|
| init | 2.288 / 2.166 | 678.008 / 677.702 | 0.006 / 0.007 | 680.354 / 679.753 |
| tick | 2.083 / 2.247 | 43.941 / 43.941 | 0.005 / 0.004 | 45.912 / 46.431 |

### Final qualification and harness normalization

Main public70processes/910calls/115controls/16fresh builds/eight equal-image pairs; balanced140/1820; independent710sealed identities and667tracked source files. Complete CPU/gas/register/page/permission/source snapshots and ordered host events verify. Calibrated AddressSanitizer passes the C arena1,000lifetime controls and native/refused VM witnesses; generated machine bytes remain covered by independent literal/state witnesses rather than sanitizer instrumentation. Forced unavailable-storage execution passes28processes/364calls/46controls/eight builds/four pairs/702sealed files, with native execution/publication counts all zero and667tracked files bound to63eeaa3c04e9f3471306c8ffd51b9e6a6877b6c6.

Both helpers now freeze current HEAD by default and accept explicit exact commit IDs that must resolve to themselves. Clean checkouts no longer depend on an unreachable draft object. The kernel pair now uses identical native/control-receipt defines and parsing. Its fresh current-HEAD A/A control passes nine native gates,42processes/546calls/63controls/six fresh builds/three equal-image pairs and byte-identical baseline/current binaries, with706sealed identities/684tracked source files. Earlier kernel-only ratios used different diagnostic receipt defines and are not isolated runtime-only measurements; the matched public cohorts remain the performance-verdict evidence. An ignored-normalizer assertion accidentally allowed a shell to continue an unwanted unmatched-wrapper run, overwriting the earlier final-readiness kernel receipt. That diagnostic is retained without a runtime speed claim; the fresh matched A/A cohort replaces it. The primary public, repeated and profile receipts were unaffected.

Final LinuxARM64 passes nine shared native gates, four public builds,14processes/182calls,32refusal controls,2,863staged seals and2,846tracked files bound to63eeaa3c04e9f3471306c8ffd51b9e6a6877b6c6. Official compiler/archive identity, image/architecture/network isolation and copied state/protocol records independently verify. Container clocks are diagnostic only. Fresh broad Python discovery passes1556tests(2skipped), exit0. Production smoke passes all453modules and peer entry point. The latest published source head Compile / Smoke check passed.

### Readiness and next boundary

I am comfortable with a first merge of this opt-in slice. The PR stays draft and unmerged; defaults/backend/CLI activation and production caller-lifetime integration remain separate decisions. Native generation is qualified for macOS/LinuxARM64; x86-64 generation remains future work. Cold costs and reference-constructor scope above prevent a universal startup-speed claim.

Twelve separate full-state profile processes/156calls retain hashes and discard their clocks. Full-process sampling includes construction, inlined driver checks and validation outside the invocation clock, so it does not give invocation CPU percentages. A timed-scope profile should guide larger native-block-linking and checked native-memory/fault-prefix work. Initialization reaches1,024physical publications at82,972of1,048,576arena bytes; avoiding an arithmetic publication immediately replaced by a branch-complete version is another bounded future idea, not a measured change here.

All eight retained speed increments and the rejected publication-sealed-entry implementation remain in history. Local full report:build/pvm-arm64-jit/session-final/report.md; immutable receipts:build/tests/pvm-arm64-applications and build/pvm-arm64-jit/refusal-quality. The final local readiness receipt is bound by SHA25684d11de97d3cc4ff23a67ed7202f6604c4af69fe64b8303bd07f0d7f1c2877a6.


## Scoped invocation profiling after merge (October 28)

Merged baseline `31c7a998cf679de9bd0e9b38707313ae56b1d485`, Apple M1 Max, unchanged
October 26 compiler, checked release/ARC/Clang ThinLTO. `make profile-pvm-arm64-jit` first
produces a fresh matched application cohort and then samples its sealed images serially. No
production source or benchmark driver changes are required. The pure parser partitions exclusive
self weights by invocation ancestry, excluding benchmark construction and result checking and
avoiding inclusive-parent double counting. It refuses absent scopes and inconsistent trees.

Compiler inlining preserves `executeSelected` in the interpreted sieve image and
`runPreparedFrame` in its JIT image; both cover invocation memory construction, execution and
immutable publication. The latter excludes the outer prepared-owner lease flag operations. DOOM
uses its existing `runPreparedDoom` wrapper, including host handling. These are scopes inside the
public call clock, not a claim to account for every thin API instruction. No generated frame or
missing marker is silently attributed to a named worker. Profiles aggregate cold and reused calls;
they do not provide a warm-only breakdown, hardware counters or exact CPU percentages.

| Case/mode | Inside | Outside | Leading exclusive self samples |
|---|---:|---:|---|
| sieve/interpreter | 2481 | 10 | flatCharge: 689, flatRegisterPair: 529, runFlat: 337, flatMemoryPair: 287, flatBranch: 284, flatRegister: 232 |
| sieve/jit | 2494 | 12 | flatArmWhole: 1194, runFlat: 288, flatMemoryPair: 218, ???: 192, flatRegisterPair: 185, flatMemory: 159 |
| init/interpreter | 2377 | 83 | flatChargedShape: 1261, flatMemoryPair: 135, flatCharge: 111, flatRegisterPair: 102, eQdestroyQ_SX4demory0mace7sn0l: 86, withReplacedPages: 81 |
| init/jit | 2220 | 161 | ???: 387, flatCharge: 177, eQdestroyQ_SX4demory0mace7sn0l: 169, flatMemoryPair: 154, _platform_memmove: 150, withReplacedPages: 147 |
| tick/interpreter | 1276 | 480 | flatCharge: 217, flatRegisterPair: 203, flatMemory: 173, flatMemoryPair: 166, runFlat: 160, _platform_memmove: 90 |
| tick/jit | 1137 | 444 | flatCharge: 161, flatMemoryPair: 157, flatMemory: 153, flatRegisterPair: 130, runFlat: 117, _platform_memmove: 102 |

The fresh unchanged-source A/A application receipt passes 70 processes / 910 checked calls,
115 controls, sixteen fresh builds and eight equal-image pairs. Scoped sampling adds eighteen
processes / 234 completely checked calls, three per case/mode, with all clocks discarded. Every
raw trace/output hash, exclusive partition and complete-state parser is independently rechecked.
The final sampling adapter is separately hashed; its marker adaptation occurred after application
compilation and does not change any compiled runtime, driver, input or image.

Long sieve's largest named JIT self weight is the full native-header adapter, supporting a
bounded experiment in broader native continuations. Gameplay still emphasizes checked charging,
memory and dispatch. Initialization also exposes immutable publication and memory retirement;
more native arithmetic alone cannot remove those lifecycle costs.

A separate ignored diagnostic records exact emitted images while validating two DOOM processes /
26 calls and their complete state/events. Initialization publishes 1,024 images, of which 917
are byte-distinct: 107 exact duplicates consume 7,016 bytes. Gameplay publishes 736 images, with
701 distinct: 35 duplicates consume 1,312 bytes. This supports testing cold-only exact-image
sharing under the existing physical publication/arena bounds. It is distinct from delaying
conditional admission, whose rejected small-handoff regression remains documented above. The
instrumented diagnostic clocks are discarded and it makes no performance claim.

The initial run was invalidated by a Makefile edit during collection; two earlier scope attempts
refused missing compiler-elided markers. All failed receipts remain under
`build/pvm-arm64-jit/post-merge/`; none supplies a speed verdict. Completed scoped receipts:
`build/pvm-arm64-jit/scoped-profile/`. Publication diagnostic:
`build/pvm-arm64-jit/post-merge/publication-diagnostic/`.


### Scoped profiler reconciliation with owner policies (October 28)

The sampling adapter now replays the sealed cohort's protocol and selects its explicit runtime
owner policy for same-image v2 comparisons. Without that selection, profiling the image named
interpreter would use the new default JIT policy. Historical v1 images retain an empty override
and their existing framing. Unknown roles/protocols are refused before launching a child. Existing
sampled receipts remain historical evidence for their recorded pre-policy images. This tooling
change affects no production execution or previously compiled application image.


## Exact-image sharing trial rejected (October 28)

Prototype `cf4dea960886550e404a30348955320a90d8129e` against accepted profiling parent
`040671cc1725789f263d5609e4e660ec41535dd2`, Apple M1 Max, pinned October 26 compiler,
checked release/ARC/Clang ThinLTO. A cold-only word fingerprint followed by full word equality
shared immutable code across independent source tuples; canonical bodies were copied into a
private bounded pool. The native ABI, entry record layout, source/gas/budget/memory/host checks,
one-MiB arena and 1,024 physical-publication limit were unchanged.

The complete public cohort passed all 70 processes / 910 checked calls / 115 controls, sixteen
fresh builds / eight equal-image pairs. Independent verification reparses every measured output
and refusal, verifies 715 sealed identities, and binds both runtime source snapshots to their
exact commits. Nine native gates also passed, including shared-code count/successor isolation,
caller-buffer mutation, independent invocation registers, replacement, full-arena reuse,
forced refusal and exclusive owner controls. Correctness did not justify keeping the cost.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.415 / 3.394 | 2.535 / 2.550 | 2.519 / 2.538 | 2.537 / 2.477 | 5.984 / 5.936 | 0.738 / 0.748 | 0.421 / 0.428 |
| minimal 100000 | 4.873 / 4.894 | 4.907 / 4.878 | 4.902 / 4.899 | 4.884 / 4.897 | 5.994 / 6.011 | 1.006 / 1.001 | 0.818 / 0.815 |
| memset 100000 | 4.341 / 4.369 | 3.380 / 3.417 | 3.427 / 3.368 | 2.703 / 2.701 | 3.905 / 3.957 | 0.789 / 0.771 | 0.877 / 0.851 |
| pinky 1 | 85.004 / 85.509 | 72.479 / 70.260 | 69.874 / 69.944 | 70.210 / 70.162 | 94.203 / 94.042 | 0.822 / 0.818 | 0.742 / 0.744 |
| sieve 10000000 | 333.481 / 333.746 | 247.437 / 248.111 | 246.240 / 246.184 | 257.663 / 258.310 | 368.261 / 367.300 | 0.738 / 0.738 | 0.669 / 0.670 |
| init 0 | 320.031 / 321.757 | 195.319 / 196.007 | 196.621 / 197.435 | 196.053 / 196.996 | 678.122 / 678.116 | 0.614 / 0.614 | 0.290 / 0.291 |
| tick 0 | 40.340 / 40.328 | 36.949 / 36.739 | 37.099 / 36.953 | 33.296 / 33.252 | 43.953 / 43.874 | 0.920 / 0.916 | 0.844 / 0.842 |


DOOM initialization cold calls were 215.940 / 215.676 ms before and 242.644 / 239.971 ms
with interning. Gameplay cold calls were 47.681 / 46.641 versus 50.954 / 50.359 ms. These are
observations in both process orders, not a statistical confidence estimate. Reused results offer
no convincing useful benefit; the inconsistent Pinky baseline is retained. No speed win is claimed,
and no additional balanced cohort or Linux qualification is needed to reject this implementation.

Pinky's physical images decreased 518 to 385 and executable bytes 47,884 to 37,248, with
identical native call/operation counts. Gameplay decreased 736 to 701 publications and 55,504
to 54,192 bytes, again with identical native work. Initialization still reached 1,024 physical
publications; admitting more source entries increased native calls 21,370,154 to 22,112,142
across thirteen calls without a useful timing benefit. Diagnostic compilation CPU increased
3.979 to 27.947 ms there. Canonical words also add retained storage, so executable-byte savings
alone are not an overall memory reduction. These observations do not establish a hardware cause.

Reject the runtime pool and restore `arm64_jit.nim` exactly to the parent. Sharing-specific
witnesses are removed with the feature. Keep stronger physical-capacity witnesses: unique
unreachable tail words exhaust actual arena bytes, distinct scratch-only bodies exhaust actual
publication slots, and a bounded success count catches a broken exhaustion loop. The existing
reserved connected publication and failed-replacement preservation remain exercised.

Evidence: `build/pvm-arm64-jit/post-merge/shared-images/`, including the prototype, exact-head
qualification, complete measured receipts and independent verification. The next bounded
investigation is broader native continuations, not more coverage through extra tiny handoffs.


## Bounded two-block native continuations (October 28)

Measured runtime `296c6d08fd307a010f1e50a0d2c9e6229b7d0917` against accepted parent
`01419192effe695267a99b1c51624c8de69bebec`. The independent Linux gate is recorded below.
This extends the existing single bounded connected region from three blocks to two or three,
without increasing its publication allowance, executable arena, source map or invocation-context ABI.
All block gas/source guards, checked memory, host behavior, partial/paid fallbacks and default selection remain unchanged.

An ignored, untimed trace of the first 100,000 complete native-header edges per workload identified
81,993 adjacent eligible edges in long sieve and a repeated closed two-block round. Initialization
and gameplay did not show a frequent distinct closed pair in that bounded prefix. All three traced
processes passed thirteen complete checked calls; their clocks were discarded. This is source-edge
evidence for a general closed-round compiler, not a source-PC/opcode-specific optimization or a
claim about every program's complete working set.

Discovery observes at most eight complete visits per promoted header. An actual adjacent A→B→A
round admits two sealed pure blocks only after both existing branch capabilities are positive.
The non-executable header's existing scalar operation-count lane holds the cold probe budget;
executable body entries keep their genuine counts and the 12-byte entry layout is unchanged.
After expiry or region admission/refusal, the handler becomes the original ordinary native-header
worker, with no ongoing status/history test. Saved guard fallbacks cannot overwrite the connected
root handler. Partial/paid/gas-refused visits do not consume probes. Invocation history is cleared
on every run/host stop; cached source code retains no CPU, guest pointer or history.

The first variant `68900f8fb0aedce1998120a7733ffb2e4f78b9f0` observed every eligible native
header. Its complete 70-process cohort improved long sieve247.434/247.977→232.643/233.753ms,
but Pinky regressed70.061/70.317→71.626/71.794ms. That unbounded observation policy is superseded,
with its exact sources and independently verified receipts retained in `whole-observer-applications`.

### Public reused CPU, same-runner forward / reverse

Apple M1 Max; pinned October26 Nimony `358b9bce4dd855453f57a80a0c499b0b2e27d7ee`,
checked release/ARC/Clang ThinLTO. CPU ms; medians of calls3..12. Public calls include fresh
invocation regions and immutable publication; retained core has separate reset/publication.
Reference raw calls exclude invocation restoration/teardown and module construction.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.490 / 3.395 | 2.671 / 2.531 | 2.450 / 2.376 | 2.804 / 2.193 | 7.085 / 5.911 | 0.702 / 0.700 | 0.346 / 0.402 |
| minimal 100000 | 5.196 / 4.904 | 5.091 / 4.870 | 5.002 / 4.913 | 4.981 / 4.915 | 6.216 / 5.991 | 0.963 / 1.002 | 0.805 / 0.820 |
| memset 100000 | 4.564 / 4.341 | 3.439 / 3.482 | 3.405 / 3.529 | 2.916 / 2.696 | 4.140 / 3.948 | 0.746 / 0.813 | 0.822 / 0.894 |
| pinky 1 | 87.806 / 84.984 | 72.463 / 70.119 | 75.750 / 70.013 | 72.775 / 70.338 | 98.579 / 94.050 | 0.863 / 0.824 | 0.768 / 0.744 |
| sieve 10000000 | 337.984 / 333.735 | 249.425 / 248.216 | 230.797 / 229.419 | 233.208 / 228.480 | 374.420 / 371.062 | 0.683 / 0.687 | 0.616 / 0.618 |
| init 0 | 329.519 / 321.672 | 212.742 / 196.048 | 199.165 / 195.827 | 206.269 / 198.981 | 681.082 / 682.395 | 0.604 / 0.609 | 0.292 / 0.287 |
| tick 0 | 40.416 / 40.640 | 36.975 / 37.184 | 36.176 / 36.425 | 33.550 / 33.474 | 43.900 / 44.033 | 0.895 / 0.896 | 0.824 / 0.827 |

### Balanced independent process repeats

Five balanced ABBA blocks per case, ten processes per role, thirteen fully checked calls per
process. Each process statistic uses calls1..12. Sieve improves7.3–7.5% with non-overlapping
process ranges and all five paired blocks favoring the trial. Gameplay improves1.9%, likewise
non-overlapping and favored in all five blocks. Pinky, minimal, fill and initialization have
overlapping ranges; no material regression or useful speed gain is claimed for those cases.
Pinky's first forward-order slowdown did not recur in reverse order or balanced repeats.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.569 (2.548–2.596) | 2.377 (2.341–2.424) | 0.925 | 0.928, 0.928, 0.914, 0.924, 0.929 |
| minimal 100000 | 4.868 (4.824–4.926) | 4.866 (4.850–4.896) | 1.000 | 0.997, 1.004, 0.995, 1.008, 0.997 |
| memset 100000 | 3.433 (3.373–3.526) | 3.428 (3.373–3.542) | 0.999 | 1.013, 0.992, 1.027, 0.984, 0.985 |
| pinky 1 | 70.138 (69.821–70.487) | 70.106 (69.900–70.901) | 1.000 | 0.999, 1.003, 1.003, 1.003, 0.998 |
| sieve 10000000 | 247.612 (247.386–248.703) | 229.652 (229.222–231.994) | 0.927 | 0.928, 0.929, 0.927, 0.929, 0.927 |
| init 0 | 196.498 (195.645–198.062) | 195.774 (194.888–198.367) | 0.996 | 0.998, 0.994, 1.001, 0.990, 1.001 |
| tick 0 | 37.176 (36.815–37.517) | 36.455 (36.212–36.623) | 0.981 | 0.985, 0.969, 0.982, 0.984, 0.983 |

### Constructor and cold-call scopes

Prepared-owner construction is outside the call clock and remains visible below. The first call
includes lazy compilation/publication. These single forward/reverse cold observations are not
repeat-stable startup claims. Balanced cold process medians baseline→trial were Pinky73.671→73.533ms,
long sieve252.995→235.175ms, initialization214.922→215.024ms and gameplay48.067→47.628ms.

| Case | Constructor baseline | Constructor trial | Cold baseline | Cold trial |
|---|---:|---:|---:|---:|
| sieve 100000 | 1.630 / 1.521 | 1.577 / 1.665 | 7.840 / 7.911 | 7.687 / 7.736 |
| minimal 100000 | 0.012 / 0.010 | 0.013 / 0.010 | 5.990 / 4.942 | 5.074 / 5.027 |
| memset 100000 | 0.054 / 0.053 | 0.050 / 0.050 | 4.787 / 4.645 | 4.664 / 4.714 |
| pinky 1 | 0.473 / 0.461 | 0.490 / 0.463 | 75.277 / 72.955 | 86.815 / 73.728 |
| sieve 10000000 | 1.590 / 1.566 | 1.656 / 1.593 | 254.293 / 254.451 | 234.229 / 235.736 |
| init 0 | 8.587 / 7.706 | 8.486 / 7.597 | 225.754 / 219.585 | 225.645 / 213.433 |
| tick 0 | 7.770 / 7.701 | 7.701 / 7.764 | 46.334 / 47.263 | 50.706 / 47.704 |

Reference gameplay reused lifecycle medians (calls3..12) are reported separately:
Forward restore2.046ms, call43.900ms, teardown0.005ms, total45.926ms;
reverse restore2.216ms, call44.033ms, teardown0.005ms, total46.291ms.
Individual component medians need not sum to the median of per-call totals. Neither these
lifecycles nor retained-core clocks substitute for our full public-call measurements.

### Coverage, capacity and correctness

Across thirteen long-sieve calls, native handoffs fall395,149,781→200,149,825 while lowered
operations stay924,983,123. Native-header entries fall390,020,971→195,021,015.
Publication occupancy changes261→262 and bytes24,860→25,172: one additional312-byte connected
image. Pinky remains518publications/47,884bytes, initialization1,024/82,972 and gameplay736/55,504,
with identical lowered-operation and native-call counts on those workloads. Initialization
retains the previous three-block region. Gameplay's timing gain cannot be attributed to fewer
native transitions there; it is a whole-image/code-generation effect without a proven hardware
cause. No hardware counters or branch-miss measurements were collected.

All nine native gates pass, including728literal two-block gas/price/quota cases and6,486
whole-source two-block boundary cases against checked single stepping, both entry rotations,
partial/paid execution, faults, hosts, pricing policies and exclusive owner transfer. The unused
third counter lane stays zero for two-block code. Existing139-opcode/mixed, three-block, memory,
capacity/refusal and ownership suites remain. Probe-expiry controls prove exactly eight complete
visits without generating code themselves.

The primary cohort passes70processes/910calls/115positive/refusal controls,16fresh builds/eight
equal-image pairs and715source/input/compiler/image identities. Independent re-parsing binds
accepted and candidate source hashes to their exact commits. Balanced repeats pass140processes/
1,820calls and recheck the same seals, complete CPU/gas/register/page/permission/source snapshots
and ordered host events. Primary report SHA256:
`1fe99e4105345cf1f47647478c480b9fe4517330ce79ada334a6106ec8f1314c`; repeated report:
`bc8eb19570329ef407fdff38ca422f18f51190c92ac6109326749f8568466f79`.
Records: `build/pvm-arm64-jit/post-merge/two-block/` and the sealed application cohort.

Linux ARM64 qualification passes the same nine native gates, four public builds, fourteen
processes/182checked calls and32refusal controls. Independent re-parsing verifies2,869staged
source/input seals, every staged project file against measured296c6d08, the official pinned
compiler/archive identity, exact container image and network isolation. Native output has728literal
cases and positive transfer receipts; forced-storage refusal has no executable literal marker and
zero native transfers, while both run6,486source boundary cases. An initial independent verifier
incorrectly required the native-only literal marker in refused output; that local expectation was
corrected without changing runtime/tests/receipts. Container clocks are diagnostic only. This
satisfies the retention gate; no default change or merge is part of this trial.

The next bounded experiment is a checked native memory family. The earlier Nim-prechecked head
load remains rejected: a new trial must address boundary work itself and preserve fault/source
prefixes, permissions, fresh invocation ownership and canonical fallback.


## Native guarded unsigned word loads — retained (October 28)

Measured runtime `e4784c8811ee5b686ddc0bc93fa1903ce08a3411` against accepted continuation
parent `dda984bb539fd96176461ac5e9d17f6425d294df`. This isolated family lowers opcode130
(unsigned indirect64-bit load) followed by at least three pure register operations. All later
loads, stores, branches, hosts and unsupported boundaries remain ordinary source nodes.
The compiler admits at most64operations per fragment under the existing source-map, publication
and one-MiB arena caps; the reserved connected region and its block guards are unchanged.

Unlike the rejected earlier head-load trial, Nim does not precheck or preload the successful
memory word. Native code implements modulo-2^32 addressing, protected-prefix and conservative
last-address guards, then unsigned offset/extent checks against genuine readable private regions.
A readable contiguous extent permits one unaligned eight-byte load plus the pure suffix.
Otherwise it returns untouched to the exact original memory worker, which owns fragmented
access, permission/fault ordering and source-PC handling. Partial reservations never enter the
leaf. Full gas/source reservation and paid-block ordering remain in the existing workers.

The frame owns three base/extent/borrowed-pointer descriptors,72bytes in total, for stack/RW/RO.
They are captured after final private byte allocation and moves; in-place reset/host updates
never resize those byte buffers. Mapping/permission replacement constructs a fresh frame and
fresh descriptors before transferring its code cache. FlatStream transfers no descriptor.
Native code embeds no guest pointer and borrows the current frame's descriptors/registers only
for the synchronous call. Guard failure changes no guest register storage or memory. Successful
register publication follows the load and pure suffix. Read-only lowering needs no dirty marking.

### Public reused CPU, forward / reverse

Apple M1 Max, unchanged October26 Nimony `358b9bce4dd855453f57a80a0c499b0b2e27d7ee`,
checked release/ARC/Clang ThinLTO; CPU ms, calls3..12. Public calls include fresh private regions
and immutable result publication; core reset/publication remains separate. Reference raw calls
exclude restoration/teardown/module construction.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.410 / 3.456 | 2.369 / 2.414 | 2.299 / 2.333 | 2.147 / 2.176 | 5.952 / 6.016 | 0.674 / 0.675 | 0.386 / 0.388 |
| minimal 100000 | 4.873 / 4.952 | 4.870 / 4.904 | 4.843 / 4.923 | 4.823 / 4.883 | 6.005 / 6.096 | 0.994 / 0.994 | 0.806 / 0.808 |
| memset 100000 | 4.375 / 4.368 | 3.374 / 3.446 | 3.436 / 3.432 | 2.705 / 2.713 | 3.930 / 3.997 | 0.785 / 0.786 | 0.874 / 0.859 |
| pinky 1 | 84.970 / 86.051 | 69.954 / 70.743 | 69.659 / 70.273 | 70.606 / 71.132 | 95.807 / 95.150 | 0.820 / 0.817 | 0.727 / 0.739 |
| sieve 10000000 | 336.588 / 336.245 | 229.300 / 232.731 | 219.379 / 222.413 | 226.894 / 229.565 | 367.190 / 370.923 | 0.652 / 0.661 | 0.597 / 0.600 |
| init 0 | 324.197 / 320.964 | 197.208 / 194.917 | 197.049 / 197.159 | 195.587 / 195.591 | 678.323 / 676.841 | 0.608 / 0.614 | 0.290 / 0.291 |
| tick 0 | 41.032 / 40.545 | 37.248 / 37.037 | 36.317 / 36.017 | 33.304 / 32.946 | 44.331 / 44.291 | 0.885 / 0.888 | 0.819 / 0.813 |

### Balanced independent process repeats

Five balanced ABBA blocks/case, ten processes per role, thirteen checked calls/process, each
process statistic using calls1..12. Keep:long sieve improves4.4%, short sieve3.0%, gameplay1.2%;
all five paired blocks favor each and the process ranges do not overlap. Other differences are
within overlapping ranges; no material regression or useful gain is claimed for those cases.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.371 (2.358–2.401) | 2.301 (2.293–2.331) | 0.970 | 0.971, 0.967, 0.971, 0.969, 0.976 |
| minimal 100000 | 4.872 (4.849–4.907) | 4.854 (4.840–4.901) | 0.996 | 1.001, 0.997, 1.003, 0.996, 0.991 |
| memset 100000 | 3.446 (3.361–3.480) | 3.409 (3.367–3.472) | 0.989 | 0.997, 1.008, 0.992, 0.993, 0.987 |
| pinky 1 | 70.160 (69.918–71.023) | 69.862 (69.681–70.320) | 0.996 | 0.997, 0.995, 0.997, 0.996, 0.993 |
| sieve 10000000 | 229.503 (228.995–231.781) | 219.470 (218.987–220.654) | 0.956 | 0.956, 0.958, 0.957, 0.960, 0.952 |
| init 0 | 195.655 (194.788–197.941) | 195.888 (195.542–197.707) | 1.001 | 1.006, 0.999, 1.004, 0.999, 1.001 |
| tick 0 | 36.691 (36.504–36.763) | 36.263 (36.033–36.398) | 0.988 | 0.990, 0.988, 0.989, 0.989, 0.986 |

### Construction and cold execution

Prepared-owner construction remains separate from the first execution, which includes lazy
emission/publication and fresh invocation memory. CPU ms forward/reverse:

| Case | Constructor parent | Constructor trial | Cold parent | Cold trial |
|---|---:|---:|---:|---:|
| sieve 100000 | 1.510 / 1.751 | 1.539 / 1.560 | 7.572 / 7.567 | 7.344 / 7.566 |
| minimal 100000 | 0.010 / 0.011 | 0.010 / 0.010 | 4.916 / 5.035 | 4.883 / 4.979 |
| memset 100000 | 0.052 / 0.055 | 0.051 / 0.056 | 4.628 / 4.935 | 4.656 / 4.864 |
| pinky 1 | 0.465 / 0.459 | 0.462 / 0.499 | 73.283 / 73.555 | 73.266 / 74.967 |
| sieve 10000000 | 1.561 / 1.579 | 1.564 / 1.569 | 234.851 / 237.776 | 224.449 / 229.473 |
| init 0 | 7.958 / 8.015 | 7.737 / 7.559 | 232.886 / 222.723 | 216.789 / 215.748 |
| tick 0 | 7.775 / 7.618 | 7.810 / 7.750 | 47.714 / 46.552 | 46.075 / 46.073 |

Balanced cold medians parent→trial:short sieve7.487→7.628ms, long sieve234.521→225.609,
Pinky73.579→73.179, initialization214.566→215.569, gameplay44.896→44.642. Short sieve's
approximately0.14ms additional cold cost and larger native images are explicit tradeoffs; no
universal startup gain is claimed. Initialization adds about1ms in cold medians despite unchanged
reused speed. Independent component medians do not substitute for paired per-call totals.

Reference gameplay invocation lifecycle medians (calls3..12), separately from raw calls:
Forward restoration2.093ms/call44.331ms/teardown0.004ms/total46.408ms.
reverse restoration2.271ms/call44.291ms/teardown0.006ms/total46.617ms.

### Native coverage and capacity

Across thirteen calls, these are lowering counters, not hardware instruction counts:

| Case | Publications parent→trial | Bytes parent→trial | Native calls parent→trial | Lowered operations parent→trial |
|---|---:|---:|---:|---:|
| sieve 10000000 | 262→426 | 25,172→68,840 | 200,149,825→266,580,709 | 924,983,123→1,191,218,731 |
| pinky 1 | 518→525 | 47,884→50,064 | 31,512,494→32,354,595 | 165,076,876→168,521,851 |
| init 0 | 1,024→1,024 | 82,972→100,312 | 21,370,154→21,420,711 | 2,287,273,247→2,287,897,715 |
| tick 0 | 736→758 | 55,504→64,924 | 24,407,266→26,300,313 | 73,275,388→83,240,962 |

More operations move from checked handlers into native code; native calls increase rather than
decrease. These timings support the bounded family without making transition count a CPU-cost
oracle. Initialization still reaches1,024physical publications; the same limits remain effective.
No hardware instruction/cache/branch-miss counters were collected.

### Verification and provenance

Guard instruction encodings were checked against a local Clang ARM64 assembler reference.
Nine native gates pass, including507literal aliases/three-region/refusal cases and existing4,800
load/address/permission/partial-paid/pricing/source/owner cases. Guarded reads survive host map
changes, fast updates and transferred caches; unmapping proves native guard refusal executes no
load/suffix and the original checked worker reports the exact fault. Forced-storage refusal
executes zero native operations. Existing pure/register/branch/two-three-block, host and exclusive
ownership witnesses remain passing. The formatter rejected a one-line when/let test declaration;
it was corrected before final qualification and all timing.

Primary comparison passes70processes/910calls/115controls, sixteen fresh builds/eight equal-image
pairs and715source/input/compiler/image seals; balanced repeats pass140processes/1,820calls.
Independent re-parsing binds both runtime revisions, generated images, complete CPU/gas/register/
page/permission/source snapshots and ordered host events. Primary report SHA256:
`ed8f173412315e7c48d7eb9b9b48952634c4656f22ce962424e405b62e53fba7`; repeated report:
`36cd523d7192a5f1f3ca1d38761a2f9e8544b4691c4c7b1c5c1f38b6dd4aa1c8`.
Linux ARM64 passes nine gates, four public builds, fourteen processes/182checked calls and
32refusal controls. Independent exact-source/compiler/archive/image verification is recorded
with the local Linux receipt:2,869staged seals, all project source/helper/test/pin files bound to
measured e4784c88, official compiler archive and exact isolated ARM64 image. All container clocks
are diagnostic only.
Records: `build/pvm-arm64-jit/post-merge/checked-loads/` and the sealed public application cohort.
No default, backend, dependency or merge change is included.


### Backend-policy reconciliation (October 28)

The optimization stack is rebased onto master `ef44cba8cc3f87e00dfba7384db2f6b84cdf57ae`,
including the merged prepared-owner backend policy. Immutable `allowNative` still refuses native
preparation before scanning or allocating; frame-owned read descriptors never enter the code cache.
The comparison policy accepts a guarded native call with zero completed native operations: a
refused load guard leaves registers unchanged and resumes its canonical checked worker. Its actual
execution receipt remains interpreted. Completed operations still require a published fragment and
a call; forced interpretation and unavailable native policies still require every native counter
to be zero. Parser tests cover both the honest refusal and forged activity claims. Earlier timing
tables remain evidence for their recorded source heads, not measurements of this reconciled tree.


## Guarded scalar read-width trial — rejected (October 28)

Scope: extend the existing first-read/pure-suffix leaf from opcode130 to indirect loads124–130,
including signed8/16/32-bit extension. GP source/width/sign semantics remain those of the existing
checked memory handlers; pinned specification/toolchain inputs are unchanged. Native code uses
the same three invocation-owned descriptors and conservative complete-eight-byte guard for every
width. Narrow loads near a region end deliberately retain the canonical fallback rather than
introduce new descriptors or relax any bound. Source budgets, pricing, faults, host invalidation,
cache limits and transactional register publication are unchanged.

The trial passed7,098 independent literal width/sign/alias cases,30,144 complete-state memory
cases in both native and refused profiles, all nine native gates and both backend-policy suites.
The full cohort passed70processes/910calls,115controls,16fresh builds/eight equal-image pairs,
and721 sealed identities. Every raw process was independently reparsed, including strict
forced-interpreter zero-native receipts and current policy binary equality. Another140balanced
processes/1,820checked calls resolved the small timing differences. No hardware counters were collected.

Measured trial:`b5b8ee3e589a011664f9708d7d92cbc72cb1b258`; reconciled parent:
`9673f7a66b902a6f6783bd64c1d23947e75a8b4a`. AppleM1Max, pinned Nimony358b9bce, checked
release/ARC/Clang ThinLTO. Full receipt SHA256:
`f8cad2cc6decfe9e9a54c2fbead25e50fb163f68a2ea3bfaa93430e1b01c3a12`; balanced receipt:
`e36afea06fe367ed3a3850cefbd5452c2155f250718122d96c80d8f25560f77f`.

Balanced repeated CPU medians in milliseconds: ten separate processes per version, twelve
post-cold calls per process, five alternating ABBA blocks.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.322 (2.299–2.361) | 2.319 (2.287–2.361) | 0.999 | 0.998, 0.998, 0.996, 0.991, 1.006 |
| minimal 100000 | 4.894 (4.865–4.907) | 4.852 (4.820–4.861) | 0.991 | 0.986, 0.990, 0.996, 0.990, 0.996 |
| memset 100000 | 3.397 (3.365–3.472) | 3.439 (3.374–3.528) | 1.013 | 1.019, 1.006, 1.023, 1.000, 0.994 |
| pinky 1 | 71.073 (70.057–71.888) | 70.296 (69.689–71.886) | 0.989 | 1.009, 0.982, 0.980, 0.988, 0.993 |
| sieve 10000000 | 222.553 (220.403–225.072) | 224.259 (222.108–225.948) | 1.008 | 1.008, 1.009, 1.005, 1.007, 1.007 |
| init 0 | 195.808 (195.367–196.112) | 195.740 (195.184–198.115) | 1.000 | 1.006, 1.000, 0.999, 1.002, 0.998 |
| tick 0 | 35.368 (35.229–35.748) | 35.651 (35.535–35.780) | 1.008 | 1.008, 1.009, 1.001, 1.007, 1.011 |

Verdict:restore both runtime modules byte-for-byte from the accepted parent. Long sieve and
gameplay regress about0.8% in all five balanced blocks. Pinky's1.1% improvement overlaps the
parent range and loses one block. Minimal's0.9% change executes identical native operations/code
and is a whole-image effect, not useful evidence for wider-load lowering. This mix does not
justify expanding production native coverage. Retain the expanded full-source width/budget/fault/
replacement matrix; narrow operations intentionally exercise the existing canonical fallback.
Native literal coverage returns to the accepted64-bit family.

Complete-cohort reused CPU medians, forward/reverse, exclude the cold call and two warmups.
Public calls include fresh invocation memory and immutable publication; the reference column
contains raw interpreted calls and excludes restoration/teardown.

| Workload | Accepted JIT | Rejected trial | PolkaVM interpreted | Accepted / reference |
|---|---:|---:|---:|---:|
| sieve 100000 | 2.336 / 2.365 | 2.366 / 2.327 | 5.918 / 5.994 | 0.395 / 0.395 |
| minimal 100000 | 4.888 / 4.888 | 4.929 / 4.889 | 6.040 / 6.059 | 0.809 / 0.807 |
| memset 100000 | 3.417 / 3.486 | 3.478 / 3.530 | 3.969 / 3.966 | 0.861 / 0.879 |
| pinky 1 | 70.766 / 72.318 | 69.511 / 71.050 | 94.302 / 96.374 | 0.750 / 0.750 |
| sieve 10000000 | 224.007 / 221.476 | 223.189 / 223.510 | 369.092 / 367.240 | 0.607 / 0.603 |
| init 0 | 196.459 / 200.831 | 196.913 / 199.685 | 676.639 / 680.169 | 0.290 / 0.295 |
| tick 0 | 35.619 / 36.835 | 36.855 / 36.150 | 44.208 / 44.108 | 0.806 / 0.835 |

Constructor/cold CPU milliseconds, forward/reverse. The owner constructor is separate from
the first public invocation; cold includes lazy compilation/publication. Reference module
construction has a different scope and is not equated to our prepared-owner construction.

| Workload | Accepted owner | Trial owner | Accepted cold | Trial cold |
|---|---:|---:|---:|---:|
| sieve 100000 | 1.598 / 1.572 | 1.676 / 1.576 | 7.755 / 7.824 | 7.851 / 7.485 |
| minimal 100000 | 0.015 / 0.010 | 0.010 / 0.011 | 4.979 / 5.038 | 4.928 / 4.974 |
| memset 100000 | 0.053 / 0.052 | 0.049 / 0.053 | 4.839 / 5.034 | 5.003 / 5.119 |
| pinky 1 | 0.457 / 0.519 | 0.518 / 0.483 | 73.710 / 74.740 | 72.999 / 73.863 |
| sieve 10000000 | 1.623 / 1.607 | 1.578 / 1.592 | 239.763 / 227.465 | 228.031 / 228.048 |
| init 0 | 7.787 / 7.538 | 7.633 / 8.256 | 218.040 / 220.301 | 215.668 / 222.896 |
| tick 0 | 8.080 / 8.133 | 8.329 / 7.773 | 50.071 / 46.411 | 54.462 / 47.678 |

Reference lifecycle retained separately (median call3–12, milliseconds):

| Phase/order | Restore | Raw call | Teardown | Total lifecycle |
|---|---:|---:|---:|---:|
| init 0 | 2.207 | 676.639 | 0.005 | 678.760 |
| init 1 | 2.224 | 680.169 | 0.007 | 682.516 |
| tick 0 | 2.115 | 44.208 | 0.006 | 46.358 |
| tick 1 | 2.139 | 44.108 | 0.005 | 46.264 |

Coverage explains the tradeoff without identifying a CPU cause: gameplay lowered operations
rise83,240,962→92,157,218, but native handoffs also rise26,300,313→28,276,092. Pinky rises
168,521,851→176,702,092operations and32,354,595→33,411,690handoffs. Initialization still reaches
the1,024publication cap; its native bytes grow100,312→105,004. Long sieve adds only5,409lowered
operations over its thirteen calls, with identical266,580,709handoffs. This favors investigating
longer mixed fragments/continuations rather than indiscriminately adding short native leaves.

Receipts:`build/pvm-arm64-jit/post-merge/read-widths/`, with the complete cohort archived under
`measured-applications`; original report paths retain their pre-archive locations. No Linux timing
or correctness claim is made for the rejected runtime; the retained runtime is byte-identical to
the reconciled parent, whose native qualification passed.

Native restacking after the tooling reconciliation preserves measured source identity: rebased
trial `27a9c1cd2600999419faa671b3d74ab74a70385b` has identical production/native/witness bytes to measured `b5b8ee3e`.
The retained runtime equals parent `b1171011350b044f78523b659842ab859ba366f4` byte-for-byte. Restored native/refused witnesses
pass507/0literal cases and30,144complete-state load cases each. Twelve focused Python checks
pass; a separate26-call replay on the sealed identical images verifies explicit interpreted
zero-native and JIT-positive profiling policies, with all clocks discarded.


## Transactional native read spans — retained (October 28)

Scope: combine multiple opcode130 reads and existing pure arithmetic inside one reserved source
block, with at least four operations and the existing64-operation/1,024-word publication bounds.
Single-read leaves, all other widths, stores, branches, hosts and connected-block rules retain
the accepted implementation. No protocol, pin, default, cache capacity or memory policy changes.

The cold builder computes live-ins across the whole span. Native code keeps registers private
until every load guard succeeds; a failed later guard returns without any guest mutation, then
the original checked node replays the read/arithmetic prefix and reports its exact fault. Loads
read only exclusively owned invocation bytes. X17 retains the invocation descriptor pointer
across arithmetic's X1 scratch, without touching Apple's reserved X18 or callee-saved registers.
Code caches retain no invocation pointer. Partial reservations use original handlers throughout.
Oversized mixed code falls back to the accepted first-load path.

Measured candidate:`fe630daf0fa7951930b39142b20e626ad9574e1c`, parent
`6c91c7f5bec817f36e310b39992d4dac55b8fb8d`; AppleM1Max, pinned Nimony358b9bce,
checked release/ARC/Clang ThinLTO. The full paired receipt passes70processes/910calls,
115controls,16fresh builds/eight equal-image pairs and721 sealed identities. Every raw log,
state verdict, source revision, input/image hash and forced-interpreter zero-native receipt is
independently verified. Full report SHA256:
`d61dfcbaf087f1028b3c29b830de7e8d22c5e6e9f746d9025ba5c15200f2abe3`.

Balanced repeated CPU medians in milliseconds: ten independent processes per version, twelve
post-cold calls per process, five alternating ABBA blocks. The additional140processes/1,820calls
are independently reparsed; receipt SHA256:
`f40ec82e4787845bd465bdcfe843da08437160da0c43983a038e4fe5a72573ae`.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.313 (2.292–2.333) | 2.248 (2.231–2.280) | 0.972 | 0.968, 0.978, 0.971, 0.967, 0.983 |
| minimal 100000 | 4.877 (4.853–4.898) | 4.553 (4.529–4.568) | 0.934 | 0.930, 0.939, 0.934, 0.930, 0.933 |
| memset 100000 | 3.367 (3.312–3.409) | 3.386 (3.332–3.469) | 1.006 | 1.009, 1.012, 1.001, 1.003, 1.009 |
| pinky 1 | 71.446 (70.379–72.040) | 70.167 (69.681–71.340) | 0.982 | 0.993, 0.991, 0.983, 0.981, 0.986 |
| sieve 10000000 | 221.390 (220.219–224.218) | 213.631 (212.406–215.974) | 0.965 | 0.965, 0.966, 0.963, 0.965, 0.961 |
| init 0 | 194.915 (194.349–195.548) | 194.871 (193.760–196.771) | 1.000 | 0.998, 0.997, 1.002, 1.001, 1.006 |
| tick 0 | 35.804 (35.230–36.334) | 33.284 (33.086–34.017) | 0.930 | 0.930, 0.936, 0.937, 0.939, 0.931 |

Retain:gameplay improves7.0%, long sieve3.5%, short sieve2.8% and minimal6.6%, with all five
balanced blocks favoring the trial and non-overlapping process ranges. Pinky improves1.8% in
all five blocks, although its whole-process ranges overlap. Initialization is flat. Fill costs
about0.6% with overlapping ranges, a small explicit tradeoff rather than a claimed improvement.

Public reused CPU medians, forward/reverse, exclude the cold call and two warmups. Public
execution includes fresh invocation memory and immutable publication. Retained-core reset/
publication and reference raw calls remain separate scopes.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.381 / 3.478 | 2.308 / 2.308 | 2.228 / 2.233 | 2.055 / 2.067 | 5.957 / 5.950 | 0.659 / 0.642 | 0.374 / 0.375 |
| minimal 100000 | 4.865 / 4.872 | 4.856 / 4.867 | 4.541 / 4.549 | 4.521 / 4.505 | 5.994 / 6.013 | 0.933 / 0.934 | 0.758 / 0.757 |
| memset 100000 | 4.367 / 4.356 | 3.361 / 3.324 | 3.375 / 3.468 | 2.674 / 2.672 | 3.927 / 3.913 | 0.773 / 0.796 | 0.859 / 0.886 |
| pinky 1 | 85.329 / 84.885 | 70.637 / 70.502 | 69.837 / 69.544 | 69.746 / 69.171 | 94.192 / 93.994 | 0.818 / 0.819 | 0.741 / 0.740 |
| sieve 10000000 | 332.657 / 337.123 | 220.763 / 223.773 | 213.093 / 214.995 | 216.489 / 218.733 | 367.238 / 368.582 | 0.641 / 0.638 | 0.580 / 0.583 |
| init 0 | 343.511 / 349.377 | 194.204 / 198.612 | 194.166 / 196.883 | 194.196 / 196.742 | 671.390 / 680.288 | 0.565 / 0.564 | 0.289 / 0.289 |
| tick 0 | 39.507 / 39.456 | 35.614 / 35.389 | 33.428 / 33.371 | 30.270 / 29.919 | 43.816 / 44.001 | 0.846 / 0.846 | 0.763 / 0.758 |

Constructor and cold CPU milliseconds, forward/reverse. Owner construction is outside the
first call; lazy compilation and executable publication stay inside that cold call. Our
prepared-owner constructor is not equated with the reference module constructor.

| Workload | Parent owner | Candidate owner | Parent cold | Candidate cold |
|---|---:|---:|---:|---:|
| sieve 100000 | 1.587 / 1.547 | 1.544 / 1.561 | 7.363 / 7.393 | 8.089 / 7.816 |
| minimal 100000 | 0.012 / 0.011 | 0.010 / 0.010 | 4.868 / 4.944 | 4.629 / 4.550 |
| memset 100000 | 0.058 / 0.052 | 0.047 / 0.053 | 4.725 / 4.770 | 4.804 / 4.888 |
| pinky 1 | 0.459 / 0.460 | 0.453 / 0.456 | 73.728 / 73.968 | 73.418 / 72.903 |
| sieve 10000000 | 1.622 / 2.593 | 1.692 / 1.570 | 226.220 / 265.853 | 219.022 / 221.537 |
| init 0 | 7.797 / 7.851 | 7.585 / 7.920 | 214.790 / 221.008 | 214.690 / 217.974 |
| tick 0 | 7.533 / 7.651 | 7.719 / 7.675 | 47.615 / 45.829 | 45.179 / 44.397 |

Balanced cold medians include the same tradeoff: short sieve7.562→7.931ms, long sieve
227.583→219.142ms, minimal4.935→4.622ms, Pinky74.757→73.323ms, fill4.880→4.856ms,
initialization215.946→215.850ms and gameplay46.497→44.242ms. More cold compilation and
publication cost about0.37ms on short sieve; the warm speedup is not a universal startup claim.

Reference lifecycle medians for samples3–12, milliseconds; restoration and teardown are excluded
from the raw-call ratios above and remain visible here.

| Phase/order | Restore | Raw call | Teardown | Total lifecycle |
|---|---:|---:|---:|---:|
| init 0 | 2.205 | 671.390 | 0.006 | 673.542 |
| init 1 | 2.232 | 680.288 | 0.005 | 682.554 |
| tick 0 | 2.095 | 43.816 | 0.005 | 45.901 |
| tick 1 | 2.346 | 44.001 | 0.005 | 46.426 |

Coverage across thirteen calls, parent→candidate; these are lowered guest operations and
Nim/native handoffs, not hardware instruction/branch measurements.

| Workload | Publications | Native bytes | Native calls | Lowered operations |
|---|---:|---:|---:|---:|
| sieve 100000 | 399 → 723 | 63,516 → 362,120 | 2,648,157 → 2,699,169 | 11,877,412 → 12,479,481 |
| minimal 100000 | 3 → 5 | 316 → 1,076 | 26 → 1,300,039 | 77 → 5,200,129 |
| memset 100000 | 47 → 54 | 3,656 → 6,620 | 3,900,273 → 3,900,351 | 9,101,061 → 9,101,412 |
| pinky 1 | 525 → 606 | 50,064 → 85,604 | 32,354,595 → 36,282,987 | 168,521,851 → 184,616,372 |
| sieve 10000000 | 426 → 750 | 68,840 → 367,444 | 266,580,709 → 271,619,743 | 1,191,218,731 → 1,250,782,976 |
| init 0 | 1,024 → 1,024 | 100,312 → 174,636 | 21,420,711 → 14,936,467 | 2,287,897,715 → 2,272,368,979 |
| tick 0 | 758 → 887 | 64,924 → 145,448 | 26,300,313 → 24,869,221 | 83,240,962 → 93,369,909 |

Gameplay native handoffs fall5.4% while more work is lowered. Minimal now lowers5.2million
operations rather than77, so its improvement has genuine new coverage. Long sieve and Pinky
also gain coverage but add calls; fewer handoffs is not a universal explanation of the speedup.
Initialization remains at the1,024publication cap and below the unchanged one-MiB arena bound.
No CPU cause is inferred solely from these counters.

All nine native gates and both owner-policy suites pass. The final native/refused witnesses
include1,521/0independent literal transaction cases and51,424source-state cases each, plus the
accepted load/register/region/control/ownership cases. They cover derived-address aliases, X1
scratch survival, later guard rollback, protected/top/split/fragmented maps, gas/paid states,
every attempted prefix, depths2/3/16/32/63/64/65, oversized-code fallback, all pricing modes,
fresh-frame stream transfer and host remap/unmap. No source-budget or memory check is weakened.

Eighteen scoped sampling processes/234checked calls pass exact output/trace hashes and exclusive
weight re-parsing. All profiled clocks are discarded. These are current interpreter/JIT samples,
not a parent-vs-candidate CPU accounting experiment or hardware counters. Top current JIT self
weights across three repetitions:

| Case | Inside / outside samples | Leading exclusive self samples |
|---|---:|---|
| long sieve | 2485 / 13 | unknown470; flatArmWhole429; flatArmRegion371; callArmRegion335; runFlat182; flatArmMemory158 |
| init | 2208 / 163 | unknown388; flatCharge174; withReplacedPages161; memory retirement145; memmove143; add134 |
| gameplay | 1018 / 449 | flatCharge145; flatMemory137; flatRegisterPair123; flatMemoryPair114; flatArmBranch106; runFlat88 |

Checked memory, charging and dispatch remain visible gameplay boundaries; initialization still
contains immutable publication/retirement. Wider isolated leaves remain rejected. A future
bounded candidate is reusing a proven readable window for repeated reads whose source base
stays unchanged, retaining transactional fallback; that optimization is not implemented here.

Isolated LinuxARM64 qualification passes the same nine native gates, four fresh builds,
14public processes/182checked calls,32refusal controls and2,882staged seals. Exact committed
sources, official compiler archive/binary, image architecture, network isolation and every raw
state/control output are independently verified. Image:
`sha256:3d83326d227121156caa8e97d0eb9daef24b1c937e9e8779451f82efcdabbb60`.
Container clocks are diagnostic only; no native Linux performance claim is made.

Evidence:`build/pvm-arm64-jit/post-merge/read-spans/`, including main/repeated independent
proofs, scoped traces and Linux receipts. The existing historical scoped-profile folder was
preserved and restored; the new traces belong to this candidate alone.


## Stable-base read-window trial

This retained increment shares a readable-window proof only across unsigned indirect word reads
with one guest base slot that is not overwritten before any read. Relative offsets must share
the same low three bits and span at most 4,088 bytes. The first modulo-2^32 effective address
and final word are checked against the existing protected/top bounds; a single descriptor must
cover the complete nonwrapping window. X17 then retains only the invocation's admitted host
address, with no persistent pointer or ABI change. Reads whose bases change, derived addresses,
unaligned relative offsets and larger ranges retain the accepted independent guards.

Admission remains cold-only, within the same reserved source block and existing operation/code
caps. No guest register stores precede complete success. A refused window replays the original
checked source nodes, including split permissions, attempt prefixes and later faults.


### Qualified stable-base window verdict

**Keep the modest gameplay improvement and smaller executable image.** Five balanced ABBA
blocks give gameplay33.595→33.145ms; a separate five-block focused repeat gives
33.526→33.061ms. All ten block medians favor the candidate. This is about1.3–1.4%,
not a broad breakthrough. Long sieve costs about0.4–0.5%; fill is mixed, about0.3–1.1%
slower with overlapping process ranges. Pinky, short sieve and initialization do not establish
a useful CPU gain. Preserve these tradeoffs rather than claiming every case improves.

The initial forward gameplay parent run is anomalously high41.621ms, versus33.639ms in
reverse. It remains in the complete receipt/table and is not the verdict's basis. The balanced
repeats resolve it; no large gameplay percentage is claimed from that initial order.

Measured candidate:`7151b34de5d5b24ecf7a6524cc1fcd4212988866`; accepted parent:
`1beb23763497d63c9028c18315dc2a95df51b558`. Apple M1 Max, pinned October26 Nimony
`358b9bce4dd855453f57a80a0c499b0b2e27d7ee`, checked release/ARC/Clang ThinLTO.
The preserving publication changes documentation only after qualification. No compiler,
dependency, memory policy, backend default or cache-cap change accompanies this trial.

Repeated public CPU ms: ten independent processes per role, five balanced ABBA blocks.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| sieve 100000 | 2.271 (2.236–2.338) | 2.276 (2.248–2.314) | 1.002 | 0.993, 0.995, 0.992, 1.009, 1.012 |
| minimal 100000 | 4.593 (4.569–4.694) | 4.551 (4.524–4.708) | 0.991 | 0.986, 0.992, 0.990, 0.990, 1.009 |
| memset 100000 | 3.439 (3.389–3.514) | 3.476 (3.397–3.530) | 1.011 | 0.995, 0.992, 1.018, 1.012, 1.014 |
| pinky 1 | 70.182 (69.802–70.462) | 70.156 (69.698–70.538) | 1.000 | 0.993, 1.001, 1.003, 1.000, 1.003 |
| sieve 10000000 | 213.185 (212.927–214.988) | 214.238 (214.016–214.578) | 1.005 | 1.004, 1.006, 1.005, 1.004, 0.999 |
| init 0 | 196.834 (195.751–198.001) | 196.867 (195.220–197.939) | 1.000 | 0.998, 1.000, 1.002, 1.001, 0.997 |
| tick 0 | 33.595 (33.367–37.226) | 33.145 (32.775–33.301) | 0.987 | 0.991, 0.981, 0.935, 0.992, 0.983 |

Focused repeat:

Repeated public CPU ms: ten independent processes per role, five balanced ABBA blocks.

| Case | Baseline median (range) | Trial median (range) | Trial / baseline | Block ratios |
|---|---:|---:|---:|---|
| memset 100000 | 3.428 (3.362–3.541) | 3.438 (3.387–3.567) | 1.003 | 1.006, 1.013, 0.983, 1.015, 1.002 |
| sieve 10000000 | 213.361 (212.891–215.716) | 214.303 (213.998–215.060) | 1.004 | 1.007, 1.006, 1.000, 1.006, 0.994 |
| tick 0 | 33.526 (33.209–33.901) | 33.061 (32.954–33.260) | 0.986 | 0.982, 0.985, 0.995, 0.991, 0.983 |


Main-cohort CPU medians of samples3–12, milliseconds, forward/reverse. Public calls include
fresh invocation memory and immutable publication. Retained core uses its separately recorded
reset/publication lifecycle; its figures do not establish public API costs. Constructors and
reference restoration/teardown are outside raw-call ratios. The public interpreter column
forces the same current source's interpreter; it is not an independently timed master revision.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.403 / 3.400 | 2.277 / 2.276 | 2.366 / 2.249 | 2.039 / 2.041 | 6.032 / 5.982 | 0.695 / 0.662 | 0.392 / 0.376 |
| minimal 100000 | 4.862 / 4.846 | 4.582 / 4.603 | 4.535 / 4.597 | 4.529 / 4.552 | 6.028 / 5.994 | 0.933 / 0.949 | 0.752 / 0.767 |
| memset 100000 | 4.375 / 4.374 | 3.433 / 3.389 | 3.547 / 3.494 | 2.715 / 2.682 | 3.973 / 3.936 | 0.811 / 0.799 | 0.893 / 0.888 |
| pinky 1 | 85.025 / 84.893 | 70.311 / 70.538 | 69.903 / 70.084 | 69.398 / 69.719 | 94.383 / 94.240 | 0.822 / 0.826 | 0.741 / 0.744 |
| sieve 10000000 | 333.118 / 333.454 | 213.929 / 213.207 | 215.643 / 214.720 | 210.982 / 210.537 | 368.053 / 370.435 | 0.647 / 0.644 | 0.586 / 0.580 |
| init 0 | 340.161 / 341.248 | 196.435 / 195.901 | 197.036 / 195.312 | 195.538 / 194.849 | 673.848 / 672.696 | 0.579 / 0.572 | 0.292 / 0.290 |
| tick 0 | 40.103 / 40.080 | 41.621 / 33.639 | 33.337 / 33.392 | 30.174 / 30.392 | 44.084 / 44.108 | 0.831 / 0.833 | 0.756 / 0.757 |


Constructor and cold CPU ms, forward/reverse. Cold calls include lazy compilation/publication;
prepared-owner construction remains separate. The reference process does not emit a module
constructor clock here, so none is inferred or compared with our owner construction.

| Workload | Parent owner | Candidate owner | Parent cold | Candidate cold | Reference cold |
|---|---:|---:|---:|---:|---:|
| sieve 100000 | 1.666 / 1.659 | 1.550 / 1.597 | 8.025 / 8.529 | 8.414 / 8.105 | 6.189 / 6.062 |
| minimal 100000 | 0.015 / 0.010 | 0.013 / 0.010 | 4.727 / 4.618 | 4.637 / 4.582 | 5.969 / 6.060 |
| memset 100000 | 0.055 / 0.054 | 0.063 / 0.050 | 4.718 / 4.693 | 4.741 / 4.668 | 4.094 / 4.030 |
| pinky 1 | 0.472 / 0.487 | 0.459 / 0.474 | 74.404 / 73.282 | 73.036 / 73.285 | 94.386 / 94.285 |
| sieve 10000000 | 1.542 / 1.526 | 1.607 / 1.679 | 218.372 / 219.511 | 221.223 / 221.153 | 367.417 / 368.440 |
| init 0 | 7.499 / 7.689 | 7.609 / 7.514 | 214.539 / 220.055 | 219.974 / 216.059 | 675.146 / 673.080 |
| tick 0 | 7.648 / 7.563 | 7.875 / 7.807 | 43.982 / 43.659 | 44.587 / 43.664 | 44.143 / 44.426 |

Balanced cold medians (parent→candidate): short sieve8.087→8.060ms, long sieve219.526→220.481ms, minimal4.657→4.605ms, Pinky74.028→73.533ms, fill4.833→4.794ms, init216.905→216.328ms, gameplay43.639→43.047ms. These are startup observations, not broad constructor gains.

Reference DOOM lifecycle medians for samples3–12, ms; restoration/teardown stay outside raw-call ratios.

| Phase/order | Restore | Raw call | Teardown | Total lifecycle |
|---|---:|---:|---:|---:|
| init 0 | 1.970 | 673.848 | 0.005 | 675.806 |
| init 1 | 1.955 | 672.696 | 0.005 | 674.697 |
| tick 0 | 2.022 | 44.084 | 0.005 | 46.084 |
| tick 1 | 2.000 | 44.108 | 0.007 | 46.127 |


Every main-cohort pair has identical native publication, call, lowered-operation, branch/header
counts. Code shrinks without changing admitted source coverage or handoff count. These are
software counters, not executed hardware instructions or a CPU-cause attribution.

| Workload | Publications | Native bytes, parent → candidate | Native calls | Lowered operations |
|---|---:|---:|---:|---:|
| sieve 100000 | 723 | 362,120 → 340,444 | 2,699,169 | 12,479,481 |
| minimal 100000 | 5 | 1,076 → 880 | 1,300,039 | 5,200,129 |
| memset 100000 | 54 | 6,620 → 5,488 | 3,900,351 | 9,101,412 |
| pinky 1 | 606 | 85,604 → 70,120 | 36,282,987 | 184,616,372 |
| sieve 10000000 | 750 | 367,444 → 345,768 | 271,619,743 | 1,250,782,976 |
| init 0 | 1,024 | 174,636 → 131,400 | 14,936,467 | 2,272,368,979 |
| tick 0 | 887 | 145,448 → 123,572 | 24,869,221 | 93,369,909 |

Gameplay native bytes fall15.0%; initialization24.8%. Initialization still reaches the same
1,024-publication cap; smaller images do not establish cache-churn savings. No hardware counters
were collected. Checked memory, charging and dispatch remain the substantial next boundaries;
this small guard win is not evidence for further arbitrary emitter tweaks.

All nine maintained native gates and both owner-policy suites pass. New window witnesses cover
1,638direct native/zero-refused cases and56,800complete-source boundary cases in each native/
refused profile, including the accepted transactional witnesses. Coverage includes equal/maximal
relative offsets, wrapped displacements, unaligned original addresses, all base slots and
three descriptor positions, first/later refusal, bases changed by reads/arithmetic, differing
bases, mismatched low offset bits, large ranges, split permissions, every attempt/gas prefix,
fresh memory and existing host remapping. Independent Clang assembly confirms new encodings.

The main cohort has70processes/910checked calls,115positive/refusal controls,16fresh builds/
eight equal-image pairs and721sealed identities. Balanced repeats have140processes/1,820calls;
the focused repeat has60processes/780calls. Every raw row is independently re-parsed and bound
to exact committed sources and image hashes. Complete CPU/gas/register/page/permission/source
snapshots and ordered host-event checks pass. No source-budget or memory checks are weakened.

Isolated native LinuxARM64 passes all nine gates, four fresh builds,14public processes/
182checked calls and32refusal controls. All2,882staged files, source commit, official compiler
archive/binary, architecture/network isolation and raw outputs are independently verified. The
same new1,638/zero literal and56,800source-state witnesses pass there. Docker clocks are
diagnostic only; this establishes no native Linux performance claim.

Linux image:`sha256:c6a7af8c801d4c5f5eca338c3c5024d5aae6811713d8064a9ab40b66a8f4a330`.

Evidence:`build/pvm-arm64-jit/post-merge/read-windows/`.
Main report SHA256:`0765d8be74dbac9d32d946924f2ef3f8c30a216219216d21e7d86005c33c73b3`.
Balanced report SHA256:`a7b252d4751b23127530d80d22255c77a6baba8ab404b659e0347e639eba2591`.
Focused report SHA256:`667092ceb1e196257fb9db7429a2033af178635e68ea8c04c037c773b97b9c30`.

## Direct absolute read with cached conditional

The next local branch starts at exact merged master
`f8612e62105d1a4b446d320f87df83eafeb95819`. A sealed source sequence beginning with
one direct absolute load (opcodes 52–58), followed by at least one supported pure operation and
a conditional (81–90 or 170–175), can publish one guarded ARM64 fragment. Publication waits
until the original checked branch handler has positively cached both scalar destinations. The
fragment computes the immediate modulo 2³², checks the protected prefix and conservative
eight-byte top bound, then checks the current frame's three readable descriptors. No register
write occurs before all read guards pass. A refusal replays the original paid checked source;
partial budgets use its original barrier. Only a successful native conditional clears the paid
flag and returns a cached destination. Ordinary block charging, host work and the 1,024-entry
arena ceiling remain as before.

On macOS ARM64 with the pinned Nimony/Clang ThinLTO checked release profile, a 13-call prepared
DOOM tick comparison against exact master used samples 3–12 in each process. Across 12 balanced
process pairs, the candidate won 9; the median candidate/master CPU ratio was 0.9900. Individual
pair ratios ranged from 0.9606 to 1.0209, so this is a small, noisy local gain rather than a
hardware-cause claim. The two paired initialization comparisons were near parity; that phase
still hits the 1,024-entry cap. Tick native publications were 919→910, calls across 13 public
calls 16,066,634→16,066,627, compiled operation receipts 149,409,457→152,738,024, and code
bytes 174,828→175,428. The original branch call is replaced by a read/branch call, explaining
why the native call count barely changes even though more source operations execute natively.

The local ARM witness passes 1,640 direct literal cases across all seven signed/unsigned widths,
thirteen destination registers, three descriptor positions, both branch arms, absent/short
regions, and protected/top-address refusals. Another 122 full-frame cases compare the warm
native loop with independent single stepping across paid/unpaid entry, gas, source-attempt
budgets and memory replacement. The isolated warm loop additionally requires positive native
calls with exactly three compiled guest operations per call; the older checked-load plus native
arithmetic/branch path has only two. A build-only mutant with direct-read route admission removed
reached and failed this assertion after the independent literal cases passed. The maintained
native comparison gate requires one literal
receipt of 1,640 in native mode or zero in refused/interpreted mode, and one 122-case control
receipt in every mode; missing, repeated or cross-mode receipts are rejected. The
executable-storage-refusal build passes with zero direct native literal calls and the same
full-frame controls. Existing all-opcode and fragmented-region/host suites pass. These focused checks are macOS results; the combined Linux qualification follows below.

Local evidence:`build/pvm-arm-next/paired-public-direct-tick-extra-results.json`,
`build/pvm-arm-next/paired-public-direct-v1-tick-recheck.json`, and
`build/pvm-arm-next/arm-direct-final-witness.log` (with refusal, all-opcode and fragmented-region/
host logs beside it). The route-disabled mutant log is
`build/pvm-arm-next/arm-direct-route-mutant.log`. The final source and retained witness both passed
these focused checks; mode-specific receipt validation ran against fresh native, refused and
interpreted witness outputs.


### Combined Linux qualification

[ARM run 41221760201](https://github.com/jacogr/ragnarok/actions/runs/41221760201) passed the
maintained native gate and paired full-application comparison for source head
`74cdecf940b3cc8e1772b4164edd25283a07ed4f`. It includes both this read/branch lowering and deferred
reservation endpoint accounting. The full provenance, raw DOOM CPU values, matching-policy
interpreter ratios and explicit long-sieve tradeoff are recorded in
[deferred reservation qualification](pvm-handler-stream.md#deferred-reservation-qualification).

Against exact baseline `f8612e62105d1a4b446d320f87df83eafeb95819`, combined JIT DOOM tick CPU is
4.6–4.9% lower in both primary orders and improves in all six replay pairs. Its ratio to PolkaVM
interpreted is 0.6971/0.6984. JIT initialization changes direction across primary orders. Long
sieve JIT CPU increases in all six replays, with pooled ratio 1.014875. These native results
measure the combined stack and do not isolate this lowering's contribution.

The Linux native receipt includes all 1,640 direct literal cases and 122 full-frame controls,
with the required native/refused/interpreted mode counts. The comparison gate's two fixture
families both include the new receipts and reject their omission or truncation. Later
qualification-documentation commits preserve all tested runtime, native and harness source bytes.
