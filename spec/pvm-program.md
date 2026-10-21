# PVM program decoding, first increment

Target: Gray Paper **0.8.0**, revision
`07f041dabd073f9018b418e9ee72e79dd2185401`. `spec/pins.json` records the SHA-256
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

The one-byte table width is not restricted to 1–4 or 1–8. The pinned definition
uses E_z with z encoded as one byte, and Appendix C defines E_0. Thus width zero
encodes zero-valued entries without table payload bytes; widths above eight require zero high bytes because elements
belong to the 64-bit register domain. Jump entries may name invalid destinations;
the dynamic-jump execution rule, not deblob, rejects those destinations.
These are the raw `decodeProgram` rules. The explicit `decodeJamProgram` entry
point selects the maintainer's PolkaVM compatibility policy for JAM execution:
[GP-PVM-004/005/006/007](graypaper-discrepancies.md) reject final missing successors
and widths above4, and expose zero-width tables as semantically empty. It shares
the bounded framing/ownership implementation; it is not an alternate-format
fallback. JAM code is additionally bounded to32 MiB and declared jump counts to16 Mi entries,
before width-zero normalization. These are the pinned implementation's compatibility
bounds, distinct from caller byte/count policies and the paper's raw decoder.
Original input bytes remain copied verbatim and code offsets do not
change. The declared count is checked against the local jump ceiling before
semantic normalization. Raw and JAM program owners remain independent and
immutable; callers choose their preparation boundary explicitly.

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
literal bytes and expected operands; a compatible execution corpus remains a gate
for the interpreter increment. No upstream pins are advanced.

The [machine/memory increment](pvm-machine.md) now supplies immutable snapshots and
scalar memory access, with the approved PolkaVM memory exception ordering. Gas charging,
instruction execution, standard program initialization,
host calls, invocation wrappers and whole JAM execution remain unimplemented.
Next bounded increment: instruction execution and gas accounting.

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
