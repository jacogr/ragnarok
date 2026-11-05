# Interpreter continuation overhead

Two small changes reduce repeated work in the common checked interpreter. They preserve original
source instructions, gas accounting, attempt budgets, invocation-local state and code-owner bounds.
They introduce no opcode equation, JIT emitter change or claimed speedup.

## Host-resume cache reset

A successful `resumeFlatHostMemory` prepares the next dispatch and no longer clears the 256-entry
`dynamicOffsets` array itself. The following `runFlat` entry still clears all 2,048 bytes before
dispatch. Frame initialization, refused/fallback resumes, dirty-page handling and every other
reset remain unchanged. The successful resume path does not execute a guest instruction between
preparing the frame and that next entry.

The isolated candidate was reviewed at runtime SHA-256
`a8a6b4f395876fd400b8772e78401f25237f315cf70e137a905c4edcd7e33dbf`.
Existing `pvm_stream_host_resume` and `pvm_stream_resource_transfer_boundary` passed checked
ARC/Clang ThinLTO ARM profiles. Source-bound generated C and linked inspection retained the
`runFlat` clear and confirmed that successful resume no longer clears those bytes. This is
correctness and lowering evidence; it does not establish a performance benefit.

## Adjacent add32 and unsigned immediate branch

Select existing `flatRegisterBranchCold[131, 83]` for genuinely adjacent `add_imm_32` and
`branch_lt_u_imm` source facts. The cold worker executes the ordinary arithmetic/branch path and
returns its actual outcome. It installs the existing fused worker only when the second handler
is the positively cached branch worker for both original arms. The fused worker uses the shared
register and branch equations and checks the second-source budget barrier before branch operands
or prepaid-state mutation. A folded noop between source facts cannot select this fusion.

Original PCs, independently addressable branch entry, prices, source attempts and refunds remain
authoritative. Charged-shape recognition, continuation limits, jump-40 handling and native
eligibility remain unchanged.

The isolated runtime SHA-256 is
`934f920b3996efccfb2f50d6017060f9fd1f14c7a0a19aa57697da498163150f`;
its final witness SHA-256 is
`4e16e0cf02702a5a4ee62a36634799ca38096ce4808768dd5221dcda4209ef43`.
The registered `pvm_stream_all_opcodes` profile enables `pvmStreamFusionReceipt`, a read-only
internal boolean observer of the selected worker and original source facts. It introduces no
frame fields or hot counters and is absent from ordinary production profiles.
The sanitizer runner explicitly admits and forwards this receipt define while rejecting native
and unknown defines. Its source binding includes the selected requirement record; calibration
controls retain their ordinary instrumented profile. Inert tooling checks cover this forwarding
and refusal, while actual fusion evidence comes from the Nim assertions.
The ARM and x86 native qualification gates likewise consume the registered receipt defines and
require the complete source-owned golden output. Their native source bindings include that output
and requirement record. Inert checks exercise the real controller paths with bounded unit plans:
missing activation, incomplete output and backend/refusal flag loss cannot pass those gates.

The witness composes public scalar `stepOnce` calls, whose single-step plan cannot select the
fused worker. Eight independent literals cover signed-32 extension, wrapping, high input bits,
negative immediates, unsigned comparison and equality. Three self-alias encodings include
saturated register IDs; two cross-lane cases distinguish source from updated destination.
For these 26 cases, adjacent/noop-gap code, first/interior entry, paid/unpaid state, six gas values
and eight attempt budgets produce 9,984 prefix comparisons. Additional assertions check cold
zero/one-source refusal, actual warm activation, invalid-target refusal, stream movement,
changed-source non-consuming rejection and one retained code lifetime with alternating register
state and both branch outcomes. Every added plan explicitly disables native selection, including
in a native-enabled build, so its activation receipt proves common-interpreter execution.

The first local run exposed a witness adaptation error: it compared raw scalar terminal PC with
the recursive execution PC. A diagnostic-only run identified actual PC 0 versus scalar PC 21 in
the first full panic case. Both failed binaries, diagnostics and source snapshots were retained.
The corrected oracle normalizes only expected halt/panic PC to zero, as required by the existing
recursive contract and checked-loop oracle. Budget, out-of-gas and other exit PCs retain the raw
scalar value. All register, gas, paid-state, remaining-attempt, source and activation checks remain.
The corrected plain and ARM receipt profiles each passed the full original output and new
assertions once. The ordinary ARM build omitted the observer; its generated frame/stream
declarations matched exactly and its linked worker stored the arithmetic result before checking
the second-source barrier and reading the branch lane. It removed the ordinary pair's indirect
worker handoff without repeating arithmetic, branch evaluation or charging.

## Combined qualification

The combined change starts from public master `66ce7c1016c38bf93b321ed552e9135699ca509f`.
It has the same runtime `src` tree as the two isolated candidates:
`fc84185af3392b5c07bbc7ccad63ef757945cbe5`, with native-header tree
`398b04102d97af98913e4f155821037ffb6921f8`. The two runtime edits are kept in separate commits.
All isolated packets remain frozen; their results do not substitute for checking the combined
source. The combined source/semantic checkpoint preceded linked execution. Four combined checked
ARC/Clang ThinLTO runs passed exact golden output: host resume and resource transfer in ARM
profiles, then all opcodes in plain and ARM receipt profiles. Their source-bound binaries and 82
generated C files remain retained. Production inspection confirmed the observer is absent, the
generated frame layout matches the receipt profile, `runFlat` still clears the 2,048-byte array,
and successful resume has no such clear. Required downstream Python receipt integration preserves
these unchanged runtime/witness/header/profile results; it does not add native-execution evidence.

The bounded combined checks ran once each and retained exact source, compiler, flags, binary and
raw output. The original halt/panic-only expected-PC correction and all other assertions remain
unchanged. Successful local checks do not substitute for exact-head Linux qualification.

No combined performance result is recorded here. Performance qualification requires the corrected
retained-reference lifecycle tooling on the PR base and meaningful exact-head ARM and x86
canonical Perf evidence, including DOOM and the other unchanged fixtures. Disassembly and
activation receipts establish mechanism and execution, not a measured benefit. The native
four-node fallback and other emitter experiments are outside this change.
