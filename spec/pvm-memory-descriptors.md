# Memory opcode descriptor experiment

## Scope and gates

The maintainer authorized the [wrapper proposal](pvm-interpreter-diagnosis.md#memory-wrapper-instruction-breakdown-and-proposed-experiment)
after the rejected memory-view experiment. Baseline is
`481d46f9` on the diagnosis branch, with runtime unchanged from merged
`98165f471684c217a6d959c1c021fd34d568ef54`. This experiment changes fixed
opcode metadata and its private scalar wrapper only. No compiler, pin, driver,
fixture, gas, memory-representation or public-result changes are included.
Gray Paper semantics and fault ordering remain those of [the machine](pvm-machine.md)
and [memory ordering](pvm-polkavm-memory-order.md) contracts.

Use one immutable256-entry `uint16` table for width, load/signed flags,
address-base register and immediate/register store source. Zero marks every
unsupported opcode. The existing successful-decode/category admission precedes
this lookup; byte-domain indexing and all scalar-memory checks remain enabled.
Do not replace checks with assumptions. Existing guarded read/write results,
physical address calculation, signed extension, PC advancement, writer activation,
snapshot ownership and fault behavior remain with their original owners.

The instruction gate is at least eight fewer exclusive wrapper instructions per
Pinky memory operation, with lower complete execution instruction totals on Pinky,
fill100000 and indirect100000. Counts may be collected locally when supported;
this ARM macOS host has no Valgrind, so use the existing calibrated Linux CI
attribution path. Reuse the retained exact baseline counters; inspect generated
C/native assembly and reconcile all exclusive totals. Instrumented clocks are
not timings.

Only after that gate passes, run the maintained full paired CI matrix in both
process orders with identical-image controls. Require repeatable Pinky improvement
exceeding control variation and no reproducible regression above2% on fill,
indirect calls or host/cross-page controls. Stop the descriptor experiment if a
gate fails; do not silently combine a frame/inlining change to rescue it.
The maintainer additionally requested the call frame as the next independent
experiment after this verdict, preserving separate attribution and gates.

## Verification plan

The existing memory-step suite independently lists all30 memory opcodes, widths
and signedness and exercises saturating/aliased register operands, all widths,
absolute/indirect and immediate/register forms, protected/cross-page/final-address
cases, gas and retry semantics, immutable snapshots and1000 ARC retirement cycles.
Add an exhaustive256-entry descriptor witness using explicit independent operand
mode expectations; unsupported entries must remain zero. Run affected execution,
scalar-memory and host-resume consumers sequentially with checks intact. Require
full-state CI matrices, strict binary/source controls and successful-decode assertion
controls before claiming qualification.

## Instruction gate: passed

[CI40177681230](https://github.com/jacogr/ragnarok/actions/runs/40177681230)
profiles exact code `6ebf75e43a8a49a0976044cc3d6a71f4c8a9941e` with the same
checked Linux x86-64 profile as the retained baseline. Offline replay verifies all
six raw profile hashes/parser outputs, generated C and pinned Rust source hashes,
strict canonical image controls and the full54-cell/2808-invocation same-image
summary. Reference memory counts exactly match the baseline on all three guests.

| Guest | Guest memory operations | Wrapper instructions/access, baseline → descriptor | Saved/access | Total native instructions, baseline → descriptor |
| --- | ---: | ---: | ---: | ---: |
| Pinky | 8,066,877 | 68.916619 →53.209559 | 15.707060 | 5,048,924,258 →4,922,217,337 (−2.5096%) |
| Fill100000 | 300,101 | 66.000933 →53.000387 | 13.000546 | 194,622,517 →190,721,040 (−2.0046%) |
| Indirect100000 | 1,000,015 | 69.400078 →52.900128 | 16.499950 | 421,594,943 →405,094,746 (−3.9138%) |

The counter gate passes. Every other native function's exclusive instruction
count exactly equals its baseline on each of the three guests: all total savings
are the wrapper savings, with no work shifted into other measured functions.
The Linux disassembly replaces bitset/range/width decoding
with one `movzwl` descriptor load and flag tests/masking. Its successful-decode
guard and existing checked memory calls remain. The six-register callee-save
frame, stack adjustment, two saved-state moves and epilogue still cost17/access;
this experiment does not claim to solve that next target. Inclusive Pinky memory
cost is218.6820/access versus the reference's33.1413/access, so the broad memory
path gap remains large even with the wrapper reduction.

The pinned formatter and all seven selected checked native suites pass:
`pvm_memory_step`, `pvm_execution`, `pvm_execution_cache`,
`pvm_memory_access_reference`, `pvm_memory_boundary_reference`,
`pvm_host_memory_reentry_reference`, and `pvm_mixed_program_reference`.
The memory-step suite includes the exhaustive descriptor witness and1000 ARC
retirement cycles; execution, cache and host-reentry ARC witnesses also retain
unchanged occupied memory.

## Timing verdict: rejected and stopped

[CI40178540066](https://github.com/jacogr/ragnarok/actions/runs/40178540066)
compares the exact `6ebf75e4` runtime with frozen baseline
`481d46f9a8823a0ffe45f4379dd106a9cc88f484` on an AMD EPYC9V74.
Both full54-cell/2808-invocation matrices pass their complete-state, source,
assertion and strict image controls; the pinned reference pack also passes.
Offline summary replay retains all cells and samples. Warmed CPU medians use
samples3 onward, in the maintained two process orders. Negative is faster.

| Workload | Policy | Candidate change, orders0 /1 | Same-image change, orders0 /1 |
| --- | --- | ---: | ---: |
| Pinky | Planned | +2.867% /+0.450% | −0.137% /+1.387% |
| Pinky | Dynamic | −3.595% /−0.435% | +1.162% /+2.057% |
| Pinky | Memo | −2.264% /−1.895% | +2.091% /−1.332% |
| Fill100000 | Planned | +0.139% /−0.300% | −0.278% /−0.073% |
| Indirect100000 | Planned | −3.577% /−3.945% | −0.432% /−0.034% |
| Memory aligned1000 | Planned | −4.690% /−6.447% | −0.575% /−0.564% |
| Memory crossing1000 | Dynamic | +2.890% /+4.260% | −0.054% /+0.710% |
| Sparse crossing1000 | Dynamic | +3.357% /+2.939% | +0.052% /−0.167% |

Planned Pinky has no repeatable gain, and dynamic crossing controls reproducibly
regress above2% beyond their small same-image variation. These fail the stated
gates despite real wrapper instruction savings and some faster aligned/indirect
cases. No follow-up descriptor variant or timing rerun is pursued. The experiment
is preserved on `codex/pvm-memory-descriptors`; no optimization PR is opened and
the active runtime returns to the original baseline. The call-frame experiment
starts separately on that original runtime, without this rejected descriptor.
Instruction counts explain work removed, not CPU time or the cause of these
policy-dependent timing effects.
