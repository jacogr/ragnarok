# Reuse the execution loop's validated instruction

## Scope and completion checks

Pinned Gray Paper 0.8.0 and all tool/reference pins remain unchanged. After register
result reuse, recursive execution still calls the operand decoder to validate the
current PC and then repeats that lookup inside private single-step dispatch.
Reuse the first private `ProgramResult[Instruction]` in the dispatch helper.

Keep exported stepping/execution APIs unchanged. Single-step callers still derive
one validated instruction from the supplied machine's own immutable program/PC.
The recursive loop obtains its result from the same program/PC before applying the
existing invalid-entry guest panic rule. A private helper consumes only those two
paths; it must retain default-owner, terminal-debt, capability, gas, memory and
snapshot checks. No unchecked mutable instruction or caller-selected owner enters
that helper. Keep all public result/ownership contracts and local budgets intact.

Require focused stepping/execution and both host-callback consumers, invalid terminal
PC/default/debt outcomes, the complete deterministic reference/native set including
dependent arithmetic chains, stable ARC observations and matched checked benchmark
binaries. Retain only a repeatable measured improvement, with raw samples and source
identities. Compiled performance and full upstream differential fuzzing stay deferred.

## Observed evidence

Selected `pvm_step`, `pvm_execution`, `pvm_host_execution` and `pvm_host_failures`
pass with stable occupied memory over 1,000 ARC cycles. These retain invalid imported
PC/default/debt, capability, budget, host failure and immutable-alias witnesses.
All fifteen pinned interpreted reference/native pairs pass, including all 85
dependent arithmetic operations and per-block shortages. The standard interpreted
benchmark, pinned formatting and inventory pass. No exported API or pin changes.

On Apple M1 Max/macOS, fixed-input matched checked ARC/Clang LTO binaries have
100 measured samples per workload/variant with three process warmups and reversed
process order halfway through ten pairs. Medians in microseconds:

| Workload | Before | After | Before / after |
| --- | ---: | ---: | ---: |
| Arithmetic, 10,000 iterations | 2,338.73 | 1,973.77 | 1.18× |
| Aligned memory, 1,000 iterations | 596.65 | 546.00 | 1.09× |
| Crossing memory, 1,000 iterations | 757.67 | 704.65 | 1.08× |
| Aligned host/memory, 1,000 iterations | 840.44 | 779.25 | 1.08× |
| Crossing host/memory, 1,000 iterations | 1,013.81 | 954.79 | 1.06× |

Every paired arithmetic median improves, with ratios 1.156–1.196; smaller changes
retain their complete samples rather than selecting favorable passes. Raw inputs,
binary/source hashes, load observations and samples are retained locally under
`build/pvm-execution-decode-profile/`. There is no affinity/frequency isolation or
exact-head Linux timing claim. Normal Actions reporting remains interpreted-only.
