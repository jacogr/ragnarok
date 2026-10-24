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

## Sustained decoded working sets, 2026-10-24

The maintained Pinky frame executes32,055,270 PVM instructions. A separate checked
diagnostic snapshot of the current32-slot decoder cache records30,934,880 actual
decoder calls: roughly96.5% of execution requests. This excludes pricing probes.
Complete reference CPU/gas/pages/permissions/source checks still pass; instrumented
timings are discarded. A small256-entry spill prototype still decodes roughly63%
of requests and slows planned Pinky. A4096-entry prototype instead identifies enough
reuse to justify a larger bounded working set. These counts guide the experiment;
they are not native hardware instruction or latency measurements.

The original32-slot natural/paired fast path remains first. Only after32,768
successful decoder misses does an invocation allocate one private4096-entry spill
with2048 two-way sets. Complete successful scalar `ProgramResult[Instruction]`
copies carry their original PC tags. Failed decodes never insert or advance the
saturating threshold counter. Multiplicative hashing selects eleven bits; replacement
alternates the two ways without a growing counter. Hits neither promote into the
small table nor alter replacement state. Decode/allocation/replacement work remains
in a non-inlined cold helper; successful spill reads stay directly in the lookup.

This preserves small-invocation behavior while charging a bounded memory cost only
under sustained decode pressure. The measured checked target has56-byte instructions
and64-byte instruction results:262,144 bytes of results plus2048 replacement flags,
or258KiB of payload before ARC/allocator overhead. A new invocation starts empty;
there is no input-sized growth, program preparation, opcode fusion or public resource
option. Other targets may have different object layouts.

The spill stores no program/machine/memory/callback owner and no guest balance. The
invocation's immutable program stays retained independently across host continuations;
nested calls and later calls own different caches even at identical PCs. The lookup's
cursor borrows only the private spill owner during a callback-free synchronous read;
no mutation or owner replacement occurs before a hit returns its copied result.
Each actual instruction still consumes one attempt and performs normal capability,
gas, control, host/fault and source-snapshot checks. Cached operands do not certify
paid gas or authorize an address from another program.

An exact final-candidate diagnostic records1,357,193 actual decodes,28,907,860 spill
hits and1,790,217 small-cache hits for the same32,055,270 requests. All state checks
pass. The raw baseline/capacity study and final counted sources are under
`build/pvm12/decoder-counts/` and`build/pvm12/decoder-final-counts/`; those durations
are not benchmark evidence.

### Qualification and observed timing

The cache suite builds4500 distinct literal addition instructions and executes ten
rounds, crossing both the allocation threshold and the4128 available positions.
Varying immediates expose wrong-PC hits. Dynamic, complete-plan and cold/warm lazy
policies must match the complete public-single-step CPU/gas result, exact attempt
boundary, unaffordable entry and unchanged source. The independent two-byte framing
helper admits code below16KiB with a32KiB caller blob policy for these larger cases.

Dense host cases re-enter the original program after a nested dense invocation with
different operands at identical PCs. Both callback APIs, second-callback refusal and
one-less step budget retain exact CPU/context/source behavior in all pricing modes.
Four repeated dense host groups have balanced occupied memory. The existing1000-cycle
ARC loop now also creates/destroys a sustained-pressure decoder spill every cycle;
the observed occupied-memory count is unchanged before/after all1000 cycles.

Against the preceding lazy-price-cache layer`4f55311b`, matched checked ARC/Clang
ThinLTO binaries retain two opposite process orders on seven real inputs and all
three pricing modes:1092 complete-state-checked invocations. CPU medians in
milliseconds on M1 Max/macOS, with preparation excluded:

| Input | Pricing | Parent | Decoded spill | Change |
| --- | --- | ---: | ---: | ---: |
| Indirect calls100,000 | Dynamic | 26.253 | 24.502 | -6.7% |
| Indirect calls100,000 | Complete plan | 26.186 | 24.180 | -7.7% |
| Indirect calls100,000 | Lazy memo | 26.462 | 24.644 | -6.9% |
| Pinky frame | Dynamic | 2,714.199 | 2,553.535 | -5.9% |
| Pinky frame | Complete plan | 664.095 | 489.726 | -26.3% |
| Pinky frame | Lazy memo | 743.845 | 569.726 | -23.4% |

An additional936-invocation control comparison reproduces the indirect-call gains
at roughly7–8%; a separate52-invocation planned-Pinky comparison reproduces its26%
gain. Sieve and memory-fill differences mostly remain within3%, so no improvement
is claimed there. Smaller synthetic workloads are qualified separately. An owner-only
cursor in the public operand decoder removed a retain/release pair in generated C
but improved planned Pinky less than2%; it was rejected. The public operand decoder
is unchanged. No exact-head Linux performance or whole-JAM throughput is claimed.

The selected cache, host-memory-reentry and mixed-policy suites pass; the cache ARC
report retains238144 occupied bytes before/after1000 cycles with its larger shared
fixtures alive. The original429-invocation calibrated census, nine affected Python
guards, inventory and pinned formatting pass. Two complete synthetic comparisons each
validate1716 invocations. The first synthetic timing run overlapped formatting and
is retained as noisy evidence; the uncontended repeat does not reproduce its large
mixed-bit regression. The smallest planned four-instruction case changes from0.125
to0.166µs (one observed sample quantum), and some other small cells vary a few
percent. There is no universal small-invocation speed claim. Raw data and the exact
source/binary identities are under`build/pvm12/decoded-large-paired.json`,
`build/pvm12/decoded-synthetic/` and the adjacent build/guard logs.
