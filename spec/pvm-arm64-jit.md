# Local ARM64 JIT experiment

## Scope and authority

Draft tracking work based on merged interpreter master
`ac4ba21c1486b24ad8ec8967de3208bf7cb470b1`. GP 0.8.0 and the existing PVM feature contracts
remain authoritative; pinned PolkaVM is a cross-check. This is an optional local experiment,
not a default engine, supported backend, CI requirement or completed compiler.
The October 26 Nimony pin, checked release, ARC and Clang ThinLTO remain unchanged.

## First executable increment

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
