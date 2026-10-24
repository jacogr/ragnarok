# Reusing validated control successors

## Scope and closure argument

Continuing control instructions formerly called `instructionOpcode` again after selecting their
successor. Selection already supplies the complete executable-location fact under the unchanged
Gray Paper control contract. This layer removes that duplicate query without changing any public
API, program preparation, opcode class, pricing policy, or specification/toolchain pin.

The private instruction evaluator receives the genuine decoded result for its immutable program
and current PC. Static jump and conditional operands retain their sealed owner-bound block-target
fact; capture proves that a block target is an in-range marked instruction. Negative mathematical
destinations still fail before subtraction. Conditional branches validate both their target and
sequential successor before choosing either, regardless of the predicate. A present sequential
successor of a terminating instruction is a genuine instruction and block boundary. Opcode1 uses
that same sealed fact. Final unconditional back edges require no sequential successor.

Dynamic jumps still wrap the address to32 bits, handle the halt sentinel, reject zero and odd
addresses, and resolve an existing table ordinal into a genuine basic-block target. The invocation
cache supplies only a previously completed positive lookup for this same immutable program.
Invalid targets remain guest panics. Load-and-jump reads its original target operands before its
specified destination write, including aliases, and retains that write on panic or halt.

No program mutation or host callback occurs between successor selection and the removed query.
Panic/halt skip that query already. Opcode2 retains the existing nonterminator fallthrough check;
scalar faults retain their original causing PC and access ordering. Public entry validation,
capability checks, gas pricing/affordability, local limits and host response validation remain.
This closed private invariant does not authorize trusting caller-edited instruction copies.

## Verification

The existing invocation-cache suite now frames every nontrapping control family independently,
including aliased dynamic load-and-jump. Four register patterns and paid/unpaid entry cover literal
successor PC7, exact gas, every register, paid status and unchanged source CPU. Public dynamic and
complete-plan single stepping validate that successor; all three invocation pricing modes check
one-attempt refusal followed by a second-attempt trap with independent pricing.

Negative dynamic cases cover operand-byte/out-of-code targets, absent ordinals, zero/odd addresses
and halt precedence. Each preserves the specified load mutation, including the alias, while an
unaffordable instruction refuses before mutation. Every conditional and opcode1 also run without
a sequential successor; conditional back targets remain valid but the missing successor panics
regardless of predicate. A final unconditional self-jump pays for each completed back edge before
OutOfGas. Existing target-cache collisions, nested callbacks and balanced ARC cycles remain controls.

The independent Python pipeline model prices the exact raw partitions, including the2-gas trap.
Selected native stepping, jump-table, gas-plan/memo, mixed-program and host memory-reentry suites
retain their state and ownership assertions. Exact local logs and build identities are retained
under `build/pvm11/control-successors/`.

## Local measurements

Two reversed-order paired comparisons replay the maintained indirect-call, memory-fill and sieve
guests at limits1000 and100000 under dynamic, complete-plan and lazy-memo pricing. Each retains936
full-state validated invocations, including cold samples and preparation observations. The second
comparison's large-workload CPU medians in milliseconds are:

| Guest | Dynamic before/after | Complete plan before/after | Lazy memo before/after |
| --- | ---: | ---: | ---: |
| Indirect calls | 26.838 /26.709 | 26.529 /26.370 | 27.177 /27.230 |
| Memory fill | 12.731 /12.165 | 11.700 /11.088 | 12.609 /12.056 |
| Sieve | 16.527 /16.032 | 11.530 /10.979 | 12.900 /11.271 |

Memory-fill improves roughly3–5% and sieve roughly2–13% across both comparisons. Indirect-call
results are essentially unchanged. Generated-code effects contribute; these measurements do not
count eliminated lookups. An additional1716 validated synthetic invocations cover eleven guests
under all policies. Most medians improve or remain close; planned mixed-bit operations regress3.3%
(65.792 to67.958 microseconds), an explicit local tradeoff rather than a universal speedup.

Raw samples remain in `build/pvm11/scalar-copy/control-successors{,-final}-paired.json` and the
synthetic results directory. These checked ARC/Clang ThinLTO observations use Apple M1 Max/macOS;
they establish neither Linux performance nor whole-JAM throughput. M1 framing remains complete
within its documented scope; full state serialization and whole-JAM/STF equivalence remain open.
Fuzzing remains paused pending maintainer Daybreak access.
