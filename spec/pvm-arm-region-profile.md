# ARM region-entry and selection investigation

Independent draft stack1786 above the rejected capacity evidence. Production/runtime sources
remain identical to the current accepted capacity-evidence parent. The original
pre-upgrade parent was23f8929dabc630e0c8842e9058e0c55ce6c4a5bd. No default,
admission, code emission, checked memory, host, gas, source-budget or ownership change is included.

The previous eight-slot trial regressed sieve despite identical native work/handoff counts. This
investigation compares the accepted current source against explicitly supplied rejected parent
466b85687fae91ed586ad3d2953d326db170333e on one native ARM Linux runner. Normal checked
application clocks and complete reference-state checks precede instrumentation. No profile clock
is a timing and no simulated branch/cache count is a hardware measurement.

Use calibrated explicit Callgrind client-request markers in separate diagnostic images on
Linux ARM64. Only the test wrapper is instrumented; normal timing images are unchanged.
Two fresh private-cache builds per role/family must produce equal diagnostic images, and
their runtime source hashes must match the sealed timing cohort.
Manual `jit-arm-profile` selects only the existing native ARM comparison job, native qualification,
full application cohort and six profiles: supplied baseline/current JIT, sieve100k, DOOM init and
gameplay. Every profile retains13 complete checked calls, cold dump1 and reused dump13, exact
image/input/source seals, matching native activity, self costs and call arcs. Selected/absent and
repeated/last-return controls must pass before any attribution. Unsupported instructions, missing
scopes, incomplete dumps or changed native activity fail qualification; never substitute timing
or a different execution path. Existing x86 and ordinary CI selections remain unchanged.

Inspect actual cold publication calls and warm region-entry/call accounting. Determine whether
region entry occurs on the regressed sieve path before attributing its loss to slot validation.
Use observed costs to choose the next bounded optimization. More slots, one-block admission,
new hotness rules and background compilation are outside this diagnostic step.

All native compilation, execution and profiles run on CI. Local checks cover Python parsing,
plan/environment selection, CI dispatch/matrix isolation and source inventory only.
Status: diagnostic implementation ready; exact-head native attribution pending.

## Boundary qualification and compiler reconciliation

Run40736261999 completed its normal cohort but the ARM symbol-return mechanism produced
one dump for thirteen checked calls; its workload attribution is rejected. Explicit-marker
calibration40739701219 passed selected1297, absent0, repeated2594 and last1297 instructions.
Run40740108016 passed native qualification and the normal cohort, then correctly rejected
the first diagnostic output: the baseline was explicitly requesting `jit`, unlike its normal
cohort, and emitted an additional policy receipt. Preserve strict parsing; diagnostic baseline
selection now uses the same empty/default request as its measured role. No workload
attribution from those failed attempts is accepted.

The independent PR-free base now has the exact tree of integrated x86 stack head
`c1a57ec5ac7136fede515d02b7e62d88404ac50e`, including master
`bf82cf784e97e9bef1b2bcb169b5759037caaf97`, October28 Nimony
`63fed6cb4b2f59d34c9fbb18f1796e671e2024e4` and explicit arena move resets.
Historical October26 timings retain their original compiler identity. A new diagnostic
baseline must apply only the previously rejected capacity runtime delta to the upgraded
accepted parent, with an exact tree/patch certificate; never compile an incompatible old
owner silently or relabel its historical timings as new-compiler results.

The upgraded rejected-runtime baseline is PR-free commit
`99659fad8dd81ecb49eebce9d765b487c0e9b862`, based on upgraded accepted
`13a3d5c9c39951d987b6c642c88893a608e7f92a`. Its only delta is the original
`14105fe3..466b8568` patch in `arm64_jit.nim` and `handler_stream.nim`
(94 insertions,55 deletions); arena resets remain present. It is diagnostic input,
not a proposal to restore the rejected runtime.

## Qualified October 28 result

[Run40744593111](https://github.com/jacogr/ragnarok/actions/runs/40744593111)
passed at candidate `a928295a2866e86cb18c7e1f1b9fc16bb84c4570` against
PR-free rejected-capacity baseline `99659fad8dd81ecb49eebce9d765b487c0e9b862`.
Both use October28 Nimony `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`,
checked release/ARC/Clang ThinLTO, on one native Linux ARM64 runner. The candidate
runtime is the accepted single-record parent; this PR changes only diagnostic tooling.

Independent artifact checks pass70 measured processes/910 fully checked calls,115
positive/refusal controls,16 fresh application builds/eight equal-image pairs and748
source/input/compiler/helper/image identities. Native qualification passes nine gates
and two policy controls with504 Git-verified source hashes. The six diagnostic profiles
pass78 complete reference-state/source-snapshot/ordered-host-event checks, exact native
activity matching, four scope/reset controls and eight fresh builds/four equal-image pairs.
Each diagnostic build has the sealed role's exact runtime source hashes; only the public
test wrapper has explicit markers. Every retained raw cold/reused dump and image hash
was checked independently. Intermediate dumps2..12 are runner-validated and sealed,
then removed; cold1/reused13 and the empty terminal dump remain available.

Receipt SHA256 values:

- Applications: `aa4b8c874ce127bc4e650bcb4768564b4ffb4cddb162f805091a972a9132d1a5`.
- Native: `dd4cc8c79ad112f6cc04bc72b66f5b4219251d3a2e5ab492b192da43cfc319e3`.
- Profiles: `dd45c64c869c2ea642f63feed3c7d955240f2df37156b49f77f989ecff994cf9`.

### Attribution and next bounded work

Sieve executes52,288,917 instructions with the rejected pool versus47,188,427
with the accepted single record, a5,100,490-instruction difference (9.75% of
the rejected total). Grouped exclusive region-call cost rises from7.8m to9.6m;
region matching adds3.9m while the wrapper itself falls from6.85m to6.25m.
These three functions explain essentially the entire instruction difference.
The emitted native work/calls/footprint remain identical. The failed capacity
implementation repeatedly resolves and validates the same root/slot through its
count/header/match/call helpers; source and disassembly agree with this attribution.
The candidate remains the accepted implementation; this is not a new speedup.

The larger owner also moves hot fields past600 bytes, changing load encodings,
but these profiles do not isolate its independent CPU/cache effect. Do not label
layout or simulated branch misses as a proven hardware cause. DOOM gameplay
instruction totals are essentially unchanged even while simulated branch misses
move substantially, illustrating that limitation. ARM inclusive call arcs are not
used as reliable stack causality: earlier return inference failed on real Nim calls.
Exclusive counts sum exactly to each retained raw total. No hardware counters or
simulated cache hierarchy were collected.

The accepted sieve still spends about31% of its instructions in its region wrapper
and call/accounting helper. The x86 connected-loop profile independently identifies
the same boundary class. Next test invariant/entry/accounting overhead as separate
changes; retain complete source-price matching, attempt/gas/refusal ordering and
exclusive owner checks. A bounded x86 resident invocation-counter/endpoint trial
can separately test moving existing per-block memory bookkeeping into caller-saved
registers. Do not restore eight-slot admission, broaden opcodes or alter selection
policy in either experiment. DOOM remains primarily checked charging, dispatch,
memory and publication work; source coverage is a later separate investigation.

### Calibrated diagnostic counts

Cold means the first complete call; reused is call13. Ir is executed native
instructions, not guest opcodes. Branch misses below are simulated, not hardware
measurements. Instrumented clocks are discarded.

| Scope | Runtime | Cold Ir | Reused Ir | Reused conditional misses | Reused indirect misses |
|---|---|---:|---:|---:|---:|
| sieve | Rejected pool | 119,427,066 | 52,288,917 | 208,946 | 395,198 |
| sieve | Accepted single record | 114,324,080 | 47,188,427 | 107,508 | 395,199 |
| init | Rejected pool | 3,342,289,434 | 3,239,494,654 | 2,091,140 | 23,843,722 |
| init | Accepted single record | 3,341,322,716 | 3,238,569,999 | 1,060,699 | 23,901,428 |
| tick | Rejected pool | 645,100,652 | 616,324,956 | 872,097 | 8,792,109 |
| tick | Accepted single record | 645,069,371 | 616,325,379 | 476,878 | 8,522,942 |

### Same-runner ordinary timings and lifecycle

The report's previous JIT column is the rejected upgraded baseline; current JIT is
the accepted single-record runtime. Both process orders remain distinct. Constructor,
cold call, reused public call, retained-core lifecycle and reference restoration/teardown
are separate scopes. Public calls include fresh invocation memory and immutable
publication; PolkaVM call-only timing omits its separately shown invocation restoration.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.492 / 3.512 | 3.341 / 3.352 | 3.007 / 3.012 | 2.828 / 2.803 | 6.021 / 6.133 | 0.861 / 0.858 | 0.499 / 0.491 |
| minimal 100000 | 6.359 / 6.355 | 6.137 / 6.151 | 6.001 / 6.122 | 6.539 / 6.575 | 5.467 / 5.456 | 0.944 / 0.963 | 1.098 / 1.122 |
| memset 100000 | 4.429 / 4.396 | 4.489 / 4.454 | 4.466 / 4.386 | 3.575 / 3.582 | 3.725 / 3.761 | 1.009 / 0.998 | 1.199 / 1.166 |
| pinky 1 | 95.098 / 95.487 | 87.053 / 87.583 | 86.596 / 86.845 | 87.131 / 86.936 | 87.578 / 87.426 | 0.911 / 0.909 | 0.989 / 0.993 |
| sieve 10000000 | 344.732 / 344.975 | 321.264 / 320.044 | 289.787 / 289.770 | 288.682 / 288.216 | 333.448 / 333.925 | 0.841 / 0.840 | 0.869 / 0.868 |
| init 0 | 528.799 / 535.895 | 316.523 / 323.929 | 322.248 / 321.510 | 329.075 / 337.800 | 629.065 / 624.181 | 0.609 / 0.600 | 0.512 / 0.515 |
| tick 0 | 49.755 / 49.723 | 45.991 / 46.053 | 46.340 / 46.668 | 40.762 / 41.052 | 40.034 / 40.082 | 0.931 / 0.939 | 1.158 / 1.164 |

All following CPU values are milliseconds, forward / reverse. Constructors and cold calls are separate from reused calls.

Public owner construction and cold sample zero

| Case | Interpreter owner | Previous owner | Current owner | Interpreter cold | Previous cold | Current cold | Reference cold call |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.002 / 3.000 | 2.877 / 2.833 | 2.973 / 2.826 | 8.973 / 8.906 | 10.789 / 10.806 | 10.603 / 10.402 | 6.158 / 6.476 |
| minimal 100000 | 0.014 / 0.014 | 0.014 / 0.019 | 0.015 / 0.016 | 6.456 / 6.476 | 6.090 / 6.153 | 6.227 / 6.145 | 5.556 / 5.555 |
| memset 100000 | 0.055 / 0.053 | 0.055 / 0.057 | 0.055 / 0.054 | 8.204 / 8.102 | 8.438 / 8.908 | 8.627 / 8.010 | 3.812 / 3.788 |
| pinky 1 | 0.738 / 0.755 | 0.736 / 0.691 | 0.708 / 0.686 | 97.686 / 98.055 | 91.306 / 91.838 | 90.875 / 90.899 | 87.929 / 87.498 |
| sieve 10000000 | 2.971 / 3.098 | 2.982 / 3.104 | 2.979 / 3.106 | 350.344 / 350.955 | 329.020 / 328.414 | 298.179 / 298.473 | 333.850 / 333.588 |
| init 0 | 8.538 / 8.537 | 8.555 / 8.650 | 8.562 / 8.592 | 554.110 / 550.877 | 339.822 / 347.622 | 342.720 / 352.755 | 624.471 / 629.979 |
| tick 0 | 8.510 / 8.509 | 8.588 / 8.548 | 8.478 / 8.504 | 65.379 / 64.890 | 64.341 / 63.586 | 63.903 / 64.038 | 40.315 / 40.191 |

Retained core construction and reused lifecycle; these are not public-call ratios

| Case | Facts constructor | Memory/frame constructor | Reused reset | Reused call | Reused publication | Reused total |
|---|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 2.638 / 2.648 | 0.506 / 0.518 | 0.053 / 0.051 | 2.828 / 2.803 | 0.015 / 0.014 | 2.895 / 2.868 |
| minimal 100000 | 0.011 / 0.014 | 0.064 / 0.073 | 0.002 / 0.002 | 6.539 / 6.575 | 0.002 / 0.002 | 6.542 / 6.581 |
| memset 100000 | 0.055 / 0.054 | 3.324 / 3.000 | 0.210 / 0.187 | 3.575 / 3.582 | 0.064 / 0.054 | 3.846 / 3.826 |
| pinky 1 | 0.868 / 0.820 | 0.465 / 0.405 | 0.031 / 0.030 | 87.131 / 86.936 | 0.151 / 0.147 | 87.315 / 87.119 |
| sieve 10000000 | 2.739 / 2.679 | 0.543 / 0.525 | 0.056 / 0.054 | 288.682 / 288.216 | 0.295 / 0.285 | 289.035 / 288.571 |
| init 0 | 8.561 / 8.553 | 13.473 / 13.994 | 6.852 / 6.914 | 329.075 / 337.800 | 0.031 / 0.031 | 335.954 / 344.668 |
| tick 0 | 8.565 / 8.504 | 13.962 / 13.567 | 6.174 / 6.024 | 40.762 / 41.052 | 0.030 / 0.031 | 46.926 / 47.112 |

Reference DOOM invocation lifecycle; module construction remains separate

| Case | Restore | Call | Teardown | Total |
|---|---:|---:|---:|---:|
| init | 2.591 / 2.518 | 629.065 / 624.181 | 0.223 / 0.197 | 631.860 / 626.914 |
| tick | 2.726 / 2.317 | 40.034 / 40.082 | 0.201 / 0.077 | 42.986 / 42.493 |

Current public native totals across all thirteen calls; source attempts are per retained-core call, not hardware instructions

| Case | Publications | Native calls | Lowered operations | Code used bytes | Conditional calls | Whole-header calls | Compilation CPU | Source attempts/call |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 723 / 723 | 2,699,169 / 2,699,169 | 12,479,481 / 12,479,481 | 340,444 / 340,444 | 1,970,793 / 1,970,793 | 1,952,516 / 1,952,516 | 1.675 / 1.652 | 1,166,742 / 1,166,742 |
| minimal 100000 | 5 / 5 | 1,300,039 / 1,300,039 | 5,200,129 / 5,200,129 | 880 / 880 | 12 / 12 | 0 / 0 | 0.082 / 0.124 | 2,000,035 / 2,000,035 |
| memset 100000 | 54 / 54 | 3,900,351 / 3,900,351 | 9,101,412 / 9,101,412 | 5,488 / 5,488 | 3,900,151 / 3,900,151 | 1,300,084 / 1,300,084 | 0.201 / 0.190 | 1,200,349 / 1,200,349 |
| pinky 1 | 606 / 606 | 36,282,987 / 36,282,987 | 184,616,372 / 184,616,372 | 70,120 / 70,120 | 21,030,287 / 21,030,287 | 13,669,609 / 13,669,609 | 1.066 / 1.043 | 32,055,270 / 32,055,270 |
| sieve 10000000 | 750 / 750 | 271,619,743 / 271,619,743 | 1,250,782,976 / 1,250,782,976 | 345,768 / 345,768 | 199,590,176 / 199,590,176 | 195,021,015 / 195,021,015 | 1.788 / 1.746 | 123,322,753 / 123,322,753 |
| init 0 | 1,024 / 1,024 | 14,936,467 / 14,936,467 | 2,272,368,979 / 2,272,368,979 | 131,400 / 131,400 | 7,243,881 / 7,243,881 | 4,205,022 / 4,205,022 | 5.450 / 5.571 | 203,298,231 / 203,298,231 |
| tick 0 | 887 / 887 | 24,869,221 / 24,869,221 | 93,369,909 / 93,369,909 | 123,572 / 123,572 | 20,525,709 / 20,525,709 | 1,809,870 / 1,809,870 | 1.560 / 1.608 | 15,523,334 / 15,523,334 |
