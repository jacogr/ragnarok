# Reusing validated instruction results for register evaluation

## Scope and ownership boundary

After block-price reuse, instruction decoding is the largest sampled native cost.
Charged stepping already has a complete `ProgramResult[Instruction]`, but the register
evaluator performs the same owner/PC lookup again. Use a register-evaluation overload
that consumes that existing private validated result, keeping the owner/PC API as a
lookup-and-delegate wrapper. The mutation equations, raw/JAM profile, gas, PC and
memory semantics remain unchanged under pinned Gray Paper 0.8.0.

Do not accept a caller-constructed mutable `Instruction` as trusted input. The result's
private tag/payload can only be published by the program module; default and failed
results must fail before reading operands or indexing registers. Its completed copied
instruction contains only scalar values, so it remains valid after the program owner
is released. Extracting and mutating an ordinary instruction copy must not alter the
private result. A checked compiler probe rejects construction at private `status` and
`completed` fields; retain that rejection as a source-owned privacy guard.

Verify all 38,977 independent register witnesses through both entry points, every
unsupported opcode, failed/default results, copied payload isolation and owner release.
Keep both decode profiles covered by the destination matrix and all reference/native
pairs. Measure matched fixed-input binaries and retain the API only for a repeatable
benefit; never remove runtime guards or accept unchecked operand values for speed.

## Observed checks and measurements

Both entry points pass all 38,977 independent register witnesses across all 85
register opcodes. Default/failed results and every unsupported opcode retain typed
errors. A native owner-release/copy-isolation witness passes. The source-owned
private-construction guard fails at the intended private `status` field after a
successful frontend control. Selected `pvm_step` and `pvm_execution` suites pass
with stable occupied memory over 1,000 ARC cycles. All fourteen pinned reference
/native pairs pass, including both operand profiles in the destination matrix.
Inventory and pinned formatting pass. No pin, instruction equation or gas rule changes.

On the same Apple M1 Max/macOS checked ARC/Clang LTO host, matched binaries and
unchanged fixed benchmark inputs yield these medians in microseconds. Each variant
has 100 measured samples per row, three process warmups, and reversed process order
halfway through ten pairs. A first run and a confirmation after concurrent builds
finished both show an arithmetic improvement of about 8%.

| Workload | Before | After | Before / after |
| --- | ---: | ---: | ---: |
| Arithmetic, 10,000 iterations | 2,417.19 | 2,239.02 | 1.08× |
| Aligned memory, 1,000 iterations | 590.08 | 573.21 | 1.03× |
| Crossing memory, 1,000 iterations | 744.27 | 729.85 | 1.02× |
| Aligned host/memory, 1,000 iterations | 818.17 | 806.79 | 1.01× |
| Crossing host/memory, 1,000 iterations | 978.75 | 966.58 | 1.01× |

The smaller changes do not establish independent improvements in memory or host
operations. There is no CPU affinity/frequency isolation or exact-head Linux timing
claim. Raw samples, both binaries, input/source hashes and load observations are
retained locally under `build/pvm-validated-register-profile/`; the normal
`make bench-pvm` report also passes both interpreted backends. Compiled comparisons
remain deferred, and full upstream differential fuzzing remains separate future work.
