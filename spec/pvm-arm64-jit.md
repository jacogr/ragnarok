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
