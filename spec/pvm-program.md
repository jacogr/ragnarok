# PVM program decoding, first increment

Target: unreleased Gray Paper revision
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` (VERSION0.8.0). `spec/pins.json` records the SHA-256
of `text/pvm.tex` as well as `text/serialization.tex`. Applicable definitions are
Basic Definition (`deblob`, `v_blob`, `v_inst`), Instructions, Opcodes and
Skip-distance (`eq:skip`, `eq:instructions`), Basic Blocks and Termination
Instructions (`sec:basicblocks`), and all thirteen operand groups in Instruction
Tables (`sec:instructiontables`). Serialization supplies canonical naturals,
little-endian fixed integers and least-significant-bit-first packed bitstrings.

## Implemented contract

`src/pvm/program.nim` validates a complete blob and an entry instruction address,
then retains one private immutable ARC-owned copy. It exposes copied instruction
operands, code length, basic-block membership and jump-table entries. Input must
remain stable during the call; it may be mutated or released afterwards. Handles
can be copied without exporting mutable storage. Ownership is acyclic.

Wire order is natural jump count, one-byte entry width, natural code length,
fixed-width jump entries, code bytes, then the packed opcode mask. Code length
also determines logical mask length; there are no additional code/mask prefixes.
Trailing bytes, noncanonical naturals and nonzero unused mask bits are rejected.

The decoder checks the entire instruction walk from zero, including valid opcode
membership and final block termination, even when entry points inside the program.
`unlikely` (2) is valid but is not a terminator. `ecalli` is not a terminator.
Skip is capped at 24 and sees an infinite set-bit suffix. An excessive unmarked
run fails when the walk lands on an unmarked byte. Operands instead see the entire
code followed by infinite zeroes: reading across a marked instruction is allowed.
Operand reads are not truncated at the next opcode. Registers saturate at 12.

Instruction operands preserve the GP A/B/D register names and X/Y immediate bit
patterns. Static offsets are exposed as signed displacements, not pre-wrapped
addresses: execution must resolve them against the instruction address and verify
basic-block membership. Non-applicable copied fields are zero; `shape` identifies
which operands are meaningful. Decoding does not validate branch destinations.

The current deblob equation bounds the one-byte table width to0–4, code to32 MiB,
and declared jump count to16 Mi entries. These apply to both decoder profiles and
are distinct from caller byte/count policies. Width zero encodes zero-valued entries
without table payload bytes. Jump entries may name invalid destinations; dynamic
execution rejects those destinations. The third register byte is masked to its low
nibble before saturation at12, matching current paper and pinned PolkaVM.

`decodeJamProgram` retains the still-scoped PolkaVM compatibility behavior for final
successor validation and zero-width tables (GP-PVM-004/006). These owners expose
zero-width tables as semantically empty. Both profiles share the framing and
ownership implementation with exactly one wire representation; no alternate-format
fallback is attempted. Original bytes and code offsets remain unchanged. Local jump
policy applies to the declared count before semantic normalization. Raw and JAM
owners remain independent immutable snapshots.

Caller policy uses separate nominal blob-byte and jump-count limits. A zero-width
table is never expanded, even with a large permitted logical count. All lengths,
products and conversions are checked before indexing or allocation. Validation
work is bounded by supplied bytes; instruction access examines at most 24 skip
bits and eight bytes per operand. Resource failures are distinct from malformed
programs; these limits are local policy, not newly introduced protocol constants.

Results have private discriminators/payloads and guarded value access. Default
results are unsuccessful. Default handles return `InvalidOwner`. Failures contain
no partial program, cursor or operands. Instruction and jump indices are distinct
nominal types, as are policy limits and register/immediate domains.

## Verification and remaining scope

The native `pvm_program` suite is registered in the dependency-free codec group
of the existing Hastur runner. It covers all opcode bytes and operand shapes,
explicit signed/unsigned boundaries, descriptor saturation, global zero-padding,
skip limits, malformed framing, huge claimed counts, table widths 0 through 255,
input ownership, default handles and deterministic malformed-input fuzzing.
Compiler rejection fixtures protect private storage/results and nominal domains.

The pinned `davxy/jam-test-vectors` revision
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` has codec, STF and trace data but no
standalone PVM instruction corpus at its top level. This increment makes no
published PVM execution-vector parity claim. Tests use independently specified
literal bytes and expected operands. Subsequent [reference comparisons](pvm-reference-runner.md)
now cover the interpreter subset through pinned public PolkaVM APIs; they do not
establish a published execution-vector or unrestricted conformance claim. No upstream pins are advanced.

The [machine/memory increment](pvm-machine.md) now supplies immutable snapshots and
scalar memory access, with the approved PolkaVM memory exception ordering.
[Charged execution](pvm-execution.md), [standard initialization](pvm-initialization.md)
and [host dispatch](pvm-host-execution.md) are implemented by separate adapters.
The [interpreter readiness map](pvm-interpreter-readiness.md) distinguishes those
contracts, focused comparison evidence and remaining specification/JAM gates.

## JAM table-profile execution witnesses

Authenticated authorization and refinement code, mandatory-entry5 accumulation and
real inner invocation now exercise GP-PVM-006 with a one-entry width0 table. A
successful load sets the dynamic address2 before jumping. Paper table semantics
would revisit entry0; the selected JAM profile instead produces Panic within the
bounded execution budget, matching PolkaVM's empty table. Width5 variants refuse
at preparation with the existing typed errors. Every declared entry has an explicit
one-entry local policy budget, so semantic rejection is distinguished from policy
exhaustion.

Inner invocation additionally checks the completed register write in the returned
E8 frame, exact reservation/refund using the separately verified block price,
outer Continue/inner Panic classification, and preserved source frame/map aliases.
All four native suites pass with their1000-cycle ARC evidence unchanged:
authorization975472, refinement25202592, accumulation269248 and inner invocation
507504 bytes. Evidence is local checked-release macOS/ARC/Clang LTO, not Linux CI.


## Captured destination decoding profile

[GP-PVM-009](pvm-destination-reference.md) requires raw paper and explicit JAM
owners to retain distinct three-register D rules: saturate the whole second operand
byte for paper, or its low nibble for the accepted implementation profile. The
private owner stores that choice through capture and execution. Original bytes and
other operand equations remain unchanged; outer/inner JAM preparation already
selects the compatibility owner.


Coverage-guided decoder testing, bounded input/replay commands and instrumentation
limits are recorded in [pvm-program-fuzzing.md](pvm-program-fuzzing.md).


## Genuine decoded fallthrough facts, 2026-10-23

`instructionHasFallthrough(decoded)` is a success-guarded query on a genuine
`ProgramResult[Instruction]`. It reports whether that instruction's sequential
successor is executable in the same immutable program. Failed/default results grant
no fact. A private scalar bit is set only by the owner decoder; extracting and
mutating public operand copies cannot modify, rebind or forge the tagged result.
The bit and operands remain valid after the source handle is released, with no
back-reference or additional owner retained.

Owner validation traversed every marked opcode with the identical bounded skip.
For an admitted marked PC, a sequential position inside the validated code extent
therefore names the next admitted instruction. `pc < codeLength` proves the decoder's
remaining-length subtractions before it compares skip; no potentially overflowing
successor addition is required to establish the fact. Final terminators report
false. In particular, Paper-profile final conditionals can be framed successfully
while lacking a fallthrough; their existing control rule still panics if either
successor is invalid. JAM-profile framing retains its stricter final-opcode rules.

Existing independently authored operand/width/marker tests now compare this query
with literal later-marker positions. Compiler rejection protects the private bit;
separate failed/default runtime probes and a genuine positive control check selection.
Cached execution tests retain results through operand-copy mutation/owner release,
check both final conditional paths and verify gas/step ordering. This adds validation
metadata, with no protocol encoding, pin, resource default or public mutable backing.


## Genuine static control targets, 2026-10-23

`instructionTargetStartsBlock(decoded)` queries a successful genuine
`ProgramResult[Instruction]`. Its private scalar fact binds the decoded operands to
static destination membership in the same immutable owner. Opcode1 uses its present
fallthrough; opcodes40,80–90 and170–175 use their signed displacement. Dynamic jumps
and noncontrol instructions report false. Failed/default results grant no query;
mutating an extracted operand copy or releasing the source handle cannot change the
original result. No owner back-reference or allocation is added.

A negative displacement is checked against the PC before subtraction. Captured PCs
fit host int and positive displacements fit signed32, proving the uint64 sum cannot
wrap. Destination extent and marker checks precede narrowing and access. A shared
private predecessor scan examines at most25 bytes and uses only the nearest marked
predecessor to establish a block boundary. Public `basicBlockStart` retains its
existing owner/address errors. Invalid mathematical targets still decode successfully
with a false fact, preserving execution's gas-first Panic ordering.

Literal tests cover all eighteen offset-bearing static opcodes, negative/self/end/
operand/interior/block targets, maximum positive displacement, and unmarked opcode
bytes. Terminating fallthrough covers all0–24 padding lengths and an absent successor.
Operand-copy/owner-release controls, three failed/default runtime controls, a genuine
positive control and a compiler rejection guard protect the result boundary.


## Captured bounded register coordinates, 2026-10-23

`instructionRegisters(decoded)` is a success-guarded query on a genuine
`ProgramResult[Instruction]`. It returns copied `RegisterSlots` with read-only
`aIndex`, `bIndex` and `dIndex` queries constrained to0–12. The owner decoder stores
these bounded coordinates alongside the original nominal A/B/D values. One private
byte-range helper implements the same GP saturation at12, preserving the separate
Paper/JAM destination rules and zero unused fields. No second encoding is accepted.

The public nominal `RegisterIndex` domain remains a byte, including its existing
out-of-range API errors. Only the private captured coordinates carry an array-bound
proof. Mutable raw `Instruction` copies cannot expose, rewrite or rebind that storage;
failed/default instruction results grant no coordinate query. `RegisterSlots` is a
plain scalar value with valid zero defaults, not an execution handle. Coordinates
and decoded operands remain usable after the source program handle is released,
without retaining a program back-reference or mutable backing.

Bounded fields let the compiler prove thirteen-register array accesses in arithmetic,
memory and control kernels. Default/invalid/unmarked-result runtime controls and a
real positive owner-release/copy-mutation control protect the query. A compiler
rejection protects the private storage, and existing literal operand/width/shape
cases compare every coordinate with its independently expected nominal value.
On the recorded ARM64 host the three-byte coordinates occupy existing padding:
`Instruction` remains56 bytes and the scalar write result remains24 bytes.
No cache capacity, preparation pass, resource default, protocol pin or runtime-check
flag changes. Timing and full composition coverage are recorded separately.

## Decoded arithmetic destination candidate, 2026-10-24

A genuine RegisterSlots copy now retains its bounded arithmetic destination as
well as the original A/B/D coordinates. destinationIndex returns that0..12 value;
non-register instructions and default coordinate copies return zero and never
authorize a write. instructionRegisters still requires a successful genuine
instruction result. The register evaluator still checks success and supported
opcode scope before using the coordinate. Public A/B/D coordinates and operand
semantics are unchanged, including saturation and source/destination aliases.

Each existing decoder family assigns A or D at its established operand decode,
removing repeated destination classification from computeRegisterWrite. The private
writeSlot stays inaccessible to callers. Moving the private targetStartsBlock byte
into existing instruction padding preserves the supported64-bit host's56-byte
Instruction and64-byte result/cache stride; RegisterSlots grows from3 to4 bytes.
No owner, allocation, dispatch representation or mutable program state is added.

Literal witnesses cover all85 arithmetic opcodes with distinct saturated source
and destination nibbles, unchanged A/B/D coordinates, extracted-copy tampering and
source retirement. A source-owned compiler rejection protects writeSlot. Existing
independent arithmetic/dependency references, register mutation, cached execution,
control and host consumers must pass, followed by paired complete-state CI.
The profile attributes roughly1.7% of planned Pinky instructions to repeated
arithmetic destination selection, but this candidate makes no timing claim before
qualification.

### Arithmetic destination CI qualification

CI40132488022 and its exact-source second attempt compare runtime fb95e370 with
9b270875 on separate AMD EPYC9V45 runners. Each passes all54 real/synthetic cells,
2808 complete-state candidate/baseline invocations,2808 identical-source control
invocations, assertion controls and the pinned interpreted reference pack. Cold
rows, all samples and opposite process orders remain in both reports.

The repeat measures planned sieve100000 -7.01/-8.22% (initial -7.47/-4.04%), memo
memory fill100000 -10.36/-10.58% (initial -7.56/-7.27%), and memo Pinky -4.73/-4.31%
(initial -2.45/-2.11%). Repeat planned Pinky changes -2.01/-1.96%, with controls
+0.08/+0.12%, but the initial -1.44/-1.69% overlaps controls -2.19/-1.04%; this
small planned gain is not generalized. Repeat dynamic Pinky -0.49/-0.29% remains
neutral. Dynamic sieve improves -8.39/-4.64% in the repeat, with controls
+8.77/+0.77%; the large first-order control drift stays explicit.

There are tradeoffs. Repeat memo aligned/crossing hosts change +2.91/+3.88% and
+2.28/+2.48%; their second-order controls drift +16.20/+12.21%, and initial host
second-order regressions +16.07/+12.93% do not repeat. No host gain is claimed.
Memo arithmetic10000 second order changes +3.28% initially and +4.19% in the
repeat. Memo alternating-blocks changes +2.31/+3.39% initially and +0.03/+9.96%
in the repeat; these regressions remain part of the review. Tiny repeat dynamic
arithmetic1/16 second orders change +125/+115ns (controls -15/-5.5ns); their cold
cost is retained, not hidden behind larger-workload percentages.

The repeat's same-job reference pack measures planned Pinky196.447ms versus
PolkaVM interpreted90.033ms (2.18x slower), and planned indirect10000013.290ms
versus3.846ms (3.46x). Ratios are not combined across runners; beating the reference
remains open. Seven selected native suites and419 production modules plus the peer
entry point pass; declared1000 ARC cycles balance. Literal85-opcode coordinates,
source/extracted-copy retirement,56/64-byte instruction/result sizes and the exact
private writeSlot rejection pass. Generated C selects one decoded byte instead of
reclassifying the destination. Publication changes only evidence and the profiler's
expanded coverage above the timed runtime; the complete feature patch remains
byte-identical. Raw first/repeat reports live under `build/pvm12/ci-40132488022/`
and `build/pvm12/ci-40132488022-attempt2/`.
