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
Inventory and pinned formatting checks pass. Exact-head Linux ARM paired interpretation/native
qualification is pending; local evidence does not establish Linux performance or x86 results.
