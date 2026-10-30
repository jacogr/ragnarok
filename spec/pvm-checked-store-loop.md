# Checked interpreter store loops

The interpreter dispatches the five-instruction `198 / 120 / 149 / 149 / 171` block through
several handler transitions on each iteration. Once the genuine terminal branch has resolved
both source arms and exactly one arm names the same block header, a checked whole-block worker
keeps backedges inside one Nim loop. Selection uses sealed opcode/coordinate facts, never guest
addresses or workload identities. This changes dispatch only; there are no new opcode equations,
memory representations, executable allocations or public APIs.

## Execution and ownership

Each iteration uses the existing complete gas/source-attempt reservation, register equations,
checked byte store and cached branch selection in their original order. A partial reservation
executes the original addressable nodes and temporary budget barrier. Store failures preserve the
already executed prefix, exact fault coordinate, paid flag and refund of unattempted reservations.
An exit arm returns to ordinary dispatch. Cold or invalid branches remain on their original path.

The exclusive stream retains only handler/source coordinates across calls. CPU, memory, dirty
pages, budgets and host observations remain invocation-owned. Memory permissions, publication,
source immutability, host adoption and repair/retry use their existing workers. This optimization
requires ordinary dynamic block pricing (`pricingKind == 0`). Complete-price plans and observable
lazy memos retain their established path. Native-enabled plans also retain their established JIT
seam; explicit interpretation uses this worker in both ordinary and native-enabled builds.

The normative behavior remains the repository-pinned Gray Paper, with the approved memory ordering
exception in [the memory contract](pvm-polkavm-memory-order.md). No dependency/specification pin
or protocol interpretation changes. The existing [handler stream](pvm-handler-stream.md),
[stepping](pvm-step.md) and [execution](pvm-execution.md) contracts still apply.

## Completion evidence

`pvm_stream_checked_store_loop` compares complete CPU/gas/paid state, remaining attempts,
recursive exit PC/reason, fault page and every mapped byte/permission against repeated public
`stepOnce` execution. Single stepping cannot select the five-instruction worker. Literal rising
store bytes reject a skipped/incorrect prefix or store, independently of the shared arithmetic
helpers. Cases cover paid/unpaid gas, every partial boundary across sixteen iterations,
read-only/missing/protected/top pages, five distinct alias roles, a committed-prefix fault,
paid suffix repair, crossing pages, resolved-stream transfer to a different invocation layout
and accepted host epochs with retained observations.

A private store-to-no-op mutation of only the fused worker must fail the independent full-page
comparison while original cold and single-step stores remain unchanged. Existing accounting,
region/host, budget/cache and memory matrices remain required affected-consumer checks.

## Local ARM assessment

The private prototype uses the complete tree of `97794e712ebb7a6e5d48b6035ef4dac29a7931ad`,
identical to merged parent `53fe8b20d291656143e3f4d7101bd90fe816f1ef`
(tree `f88b5efc24cadc76a39553db05b74a043e971593`). Final source adds explanatory comments and
expanded equivalent conditionals. Pinned Nimony/ARC/Clang/ThinLTO checked builds use the same
canonical snapshot path, frozen PolkaVM inputs, explicit public policies and shared measurement
lock. Each process has thirteen checked samples; the first three are excluded from CPU medians.

Twenty paired DOOM processes plus two assertion-negative controls pass complete CPU/memory/event
fixtures. CPU milliseconds, forward / reverse:

| Policy / phase | Parent | Candidate | Candidate / parent | Candidate / PolkaVM interpreted |
| --- | ---: | ---: | ---: | ---: |
| Interpreter init | 327.034 / 323.362 | 319.499 / 316.1745 | 0.9770 / 0.9778 | 0.4763 / 0.4715 |
| Interpreter tick | 37.314 / 37.468 | 30.704 / 30.7135 | 0.8229 / 0.8197 | 0.6940 / 0.6968 |
| JIT init | 178.473 / 176.829 | 179.068 / 176.545 | 1.0033 / 0.9984 | 0.2669 / 0.2633 |
| JIT tick | 21.319 / 21.421 | 21.300 / 21.4135 | 0.9991 / 0.9996 | 0.4815 / 0.4858 |

A further fifty microguest processes and two assertion-negative controls pass pinned prepared
states. Candidate / parent CPU medians, forward / reverse:

| Guest | Interpreter | JIT |
| --- | ---: | ---: |
| Sieve 100000 | 1.0096 / 1.0005 | 0.9798 / 1.0266 |
| Minimal 100000 | 1.0093 / 1.0026 | 1.0199 / 1.0063 |
| Memset 100000 | 0.9931 / 1.0072 | 0.9961 / 1.0028 |
| Pinky | 1.0028 / 0.9924 | 1.0070 / 1.0050 |
| Sieve 10000000 | 1.0076 / 1.0024 | 1.0169 / 1.0183 |

The local interpreter DOOM gain is substantial. Minimal and long-sieve JIT increases are visible
tradeoffs to assess on Linux ARM; unchanged native execution logic does not establish unchanged
performance. These are process-order comparisons, not confidence intervals or full-block throughput.
Do not combine this result arithmetically with older separately measured memory/native changes.

Eight affected Make/Hastur suites pass: checked-store loop, accounting boundary, memory-pair
matrix, regions/host, host resume, entry reuse, gas plan and gas memo. The new suite also passes
in a native-enabled build with explicit interpretation and resolved-stream transfer. Its final
store-suppression mutation fails the independent complete-page assertion as intended.

Ignored local receipts live under `build/pvm-checked-store-loop/{doom,micros,selected,final}`.
Inventory and scoped pinned formatting checks pass. The Linux qualification below assesses
the final runtime independently of these exploratory local measurements.

## Linux ARM qualification

Focused [ARM replay 41138997683](https://github.com/jacogr/ragnarok/actions/runs/41138997683)
passes measured runtime `acb1e76490de42e51fd5703fe5b69c682b87a9e6` against merged parent
`53fe8b20d291656143e3f4d7101bd90fe816f1ef`. The independent root audit checks 20 fresh
ARC/Clang/ThinLTO builds, 84 primary processes, 138 intended controls, 2575 role/source hashes
and 519 native source hashes, including exact paired baseline/current interpreter images.
The 60 additional fresh-process replays cover baseline/current JIT only; paired interpretation
has two primary process orders and is not included in that replay schedule.

Raw CPU milliseconds, forward / reverse:

| Policy / DOOM phase | Parent | Candidate | Candidate / parent | Candidate / PolkaVM interpreted |
| --- | ---: | ---: | ---: | ---: |
| Interpreter init | 444.515312 / 439.903668 | 442.384092 / 436.113064 | 0.995206 / 0.991383 | 0.703811 / 0.693606 |
| JIT init | 239.784192 / 233.319932 | 233.083084 / 233.557876 | 0.972054 / 1.001020 | 0.370823 / 0.371457 |
| Interpreter tick | 45.865416 / 45.557656 | 40.447876 / 40.053340 | 0.881882 / 0.879179 | 1.009111 / 0.999556 |
| JIT tick | 31.808008 / 31.612460 | 32.053648 / 31.788288 | 1.007723 / 1.005562 | 0.799688 / 0.793297 |

Linux interpreted DOOM tick is 11.8–12.1% lower, with init 0.5–0.9% lower. This is smaller
than the exploratory macOS gain. Interpreted minimal is 2.4–3.0% higher, long sieve 1.0–1.3%
higher and Pinky 0.5–0.9% higher in the paired primary processes.

**Native DOOM tick has a repeatable cost.** All six JIT replay pairs are slower; the ratio
of process-role medians is 1.010315 (31.728386→32.055672ms). The six paired ratios are
1.0080,1.0141,1.0054,1.0079,1.0128,1.0108. Native execution activity is unchanged, which
does not establish unchanged CPU performance. JIT micro replay ratios are 1.001761 minimal,
1.001284 Pinky and1.004635 long sieve. JIT init has mixed process ordering/spread, with role
medians 239.420024→234.256280ms (ratio 0.978432); no uniform init benefit is established.

The proposal retains this bounded tradeoff: a substantial interpreted application win with
explicit native application and interpreted micro costs. It does not establish a universal
speedup, x86 results or full-block throughput. Future changes must measure both policies.

Official artifact 13018768055 ZIP SHA-256:
`a3059fc1ded62be3a2518d5d68e240572fbf75e557b44c8c360f1fd51808ecc2`.
Application report SHA-256:
`01d863d52cb4b04ec2b727e554c9419c5d2d80523497f7b582b4cb9f26ac463c`.
Native report SHA-256:
`2d47a19a49b2fc8f6c49caf4b344b91bb7c831aba336f8938d2483099492e608`.
Ignored independent audit: `build/pvm-checked-store-loop/ci-arm/audit/result.json`.
Later evidence-only documentation commits reuse the identical runtime and driver source.
