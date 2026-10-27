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
