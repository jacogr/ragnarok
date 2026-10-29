# Rejected ARM connected-region capacity trial

Independent draft stack1786, parent14105fe3d85be32dc98c9f6a584ef9dd903f0a99.
The rejected one-block admission remains excluded. The measured candidate kept the accepted observed
closed two/three-block admission, eight completed discovery visits, code generation, register
allocation, block gas/source guards and immutable invocation/publication semantics unchanged.

The hypothesis was that eight append-only region records would let later useful loops coexist
with earlier ones. Candidate roots encoded a one-based slot in their unused successor lane,
preserving 12-byte per-node entries and constant-time lookup. Refusal was root-local. There was
no eviction, hotness ranking, worker thread or new opcode/shape admission. A region could not
capture another live region root as its canonical guard continuation.

The candidate retained the 1,024-publication limit and 1 MiB arena. Ordinary publications reserved
one slot for each remaining region, initially eight. Images stayed below 1,024 words and metadata
used a fixed eight-record array per exclusive stream. The reservation cost was part of this trial.

The tested candidate included 320 literal calls covering all eight slots, full publication
capacity, duplicate/refused admission, preserved old code and mismatched scalar proofs. A rejected
root preceded valid admissions to test local refusal. Two disjoint loops in one stream both
required native region activity, followed by 264 independent paid/gas/source-prefix comparisons.
All native checks and measurements ran on CI; one-block admission remained excluded.

**Rejected and restored:** production and supporting trial-only source are restored from parent
14105fe3d85be32dc98c9f6a584ef9dd903f0a99. The final layer retains this evidence. The complete
candidate and its passing witnesses remain in commit
466b85687fae91ed586ad3d2953d326db170333e; correctness did not justify its timing regressions.


## Qualified verdict

[Linux run40727783535](https://github.com/jacogr/ragnarok/actions/runs/40727783535)
passed at466b85687fae91ed586ad3d2953d326db170333e against exact immediate
parent14105fe3d85be32dc98c9f6a584ef9dd903f0a99. Both use pinned October26 Nimony
358b9bce4dd855453f57a80a0c499b0b2e27d7ee, checked release/ARC/Clang ThinLTO.
Each architecture independently passed70 measured processes/910 checked calls,115 positive/refusal
controls,16 fresh builds/eight equal-image pairs, all746 source/input/helper/image identities,
complete CPU/register/gas/page/permission/source/ordered-host-event checks and reference lifecycle
parsing. Raw logs were independently reparsed; source identities matched Git history.
ARM passed nine native/refusal/ownership gates plus two policy controls; x86 passed13 plus two.
Each native report's503 tracked source hashes independently matched the measured head.
The updated smoke run40727795083 passed. No hardware counters were collected.

ARM sieve100k regresses13.3%/12.7%; sieve10m regresses12.8%/12.0%, forward/reverse.
Native calls, operations, publications and code bytes on sieve are exactly identical to the parent.
Pinky, minimal, fill and gameplay also show no additional native coverage. Initialization saves
only78 native calls across all13 invocations, loses1,156 lowered operations and publishes seven
fewer fragments. These observations establish no useful coverage/handoff gain from capacity alone.
Initialization timings improve1.7%/1.3% and gameplay0.6%/1.1%, insufficient to offset the both-order
sieve losses. Do not infer a hardware cause solely from these software counters.

The source audit shows a plausible implementation cost worth revisiting: the new root-to-slot
validation is repeated by count/header/match/call helpers, whereas the parent directly accesses
one fixed record. It also reserves seven additional publication slots without demonstrating extra
useful native work on these workloads. Neither explanation has been isolated by a separate profile;
do not label either a proven cause. This is a rejection of this implementation, not proof that a
bounded pool can never help.

The x86 production path was unchanged; its separate runner is a control and cannot explain the
ARM regression. Do not combine timings across architectures or machines. Constructor/cold/reused
and retained-core reset/publication remain separate below. Reference module creation is not our
prepared-owner creation.

Next bounded direction: observe which region roots complete useful work before broadening
admission, and avoid repeated metadata validation in any multi-region execution interface.
Only after the dispatch cost is qualified should one-block admission compete for that capacity.
No hotness policy, one-block admission or further optimization is included here.

## Artifact provenance

Local audit copies live under ignored `build/pvm-arm-capacity/qualified-{arm,x86}/tests/`.
Canonical CI artifacts are `pvm-comparison-arm64-1` and `pvm-comparison-x86_64-1`.

| Report | SHA-256 |
|---|---|
| ARM applications | `d8a5b724355ec903b6b30dc5900250fd00c105d1fe1328bf7bfcdee454ee4f26` |
| ARM native | `df45282fc87ed3966a01240456669a03029c4698343ceb39a4f94ff5ec9c7f72` |
| x86 applications | `20858100c58f57c9bb1abb50d1d0b8613ba5eafd6d647503db4cb5b6f9e1f1bd` |
| x86 native | `e4a9b190fe1d9d6648766defcb97ec97a5644ac1f1e09fef4d17509fe438bb94` |

Initial attempts40725850869 and40726777026 stopped during compilation: first a formatter-joined
comparison token, then a uint32/int64 constant comparison. Both were corrected without changing
validation or compiler pins; only these superseded experiment runs were cancelled. Originating
logs and failed receipts remain under ignored `build/pvm-arm-capacity/`. The qualified cohort
was rerun in full; no failed or partial timing is used below.

## ARM measured candidate, not retained runtime

The following tables describe the rejected measured head. “Previous” is the retained parent;
“current” is the rejected eight-slot trial. Both process orders are shown. Reference ratios are
raw public call-only comparisons; reference lifecycle and our constructors are separate.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.497 / 3.392 | 2.992 / 2.992 | 3.389 / 3.371 | 3.198 / 3.222 | 6.036 / 6.016 | 0.969 / 0.994 | 0.561 / 0.560 |
| minimal 100000 | 6.268 / 6.196 | 5.856 / 5.857 | 5.890 / 6.004 | 6.080 / 6.091 | 5.472 / 5.533 | 0.940 / 0.969 | 1.076 / 1.085 |
| memset 100000 | 4.485 / 4.537 | 4.513 / 4.424 | 4.471 / 4.451 | 3.621 / 3.621 | 3.737 / 3.753 | 0.997 / 0.981 | 1.196 / 1.186 |
| pinky 1 | 95.402 / 95.346 | 86.700 / 86.754 | 86.509 / 86.302 | 86.747 / 86.765 | 87.850 / 87.881 | 0.907 / 0.905 | 0.985 / 0.982 |
| sieve 10000000 | 345.912 / 336.740 | 286.865 / 285.906 | 323.441 / 320.311 | 325.933 / 328.264 | 333.590 / 333.600 | 0.935 / 0.951 | 0.970 / 0.960 |
| init 0 | 536.000 / 536.230 | 331.458 / 324.785 | 325.976 / 320.723 | 338.884 / 332.245 | 628.088 / 625.142 | 0.608 / 0.598 | 0.519 / 0.513 |
| tick 0 | 51.271 / 48.758 | 46.615 / 46.536 | 46.346 / 46.015 | 41.816 / 41.662 | 40.130 / 40.093 | 0.904 / 0.944 | 1.155 / 1.148 |

All following CPU values are milliseconds, forward / reverse. Constructors and cold calls are separate from reused calls.

Public owner construction and cold sample zero

| Case | Interpreter owner | Previous owner | Current owner | Interpreter cold | Previous cold | Current cold | Reference cold call |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 2.982 / 3.034 | 2.983 / 2.900 | 2.972 / 2.850 | 8.946 / 8.852 | 10.660 / 10.565 | 10.946 / 10.870 | 6.134 / 6.155 |
| minimal 100000 | 0.015 / 0.016 | 0.015 / 0.014 | 0.017 / 0.016 | 6.396 / 6.306 | 6.073 / 6.062 | 6.110 / 6.192 | 5.566 / 5.589 |
| memset 100000 | 0.056 / 0.058 | 0.063 / 0.056 | 0.056 / 0.055 | 8.713 / 8.179 | 8.876 / 8.710 | 8.801 / 8.333 | 3.864 / 3.808 |
| pinky 1 | 0.772 / 0.758 | 0.748 / 0.743 | 0.710 / 0.741 | 98.047 / 97.999 | 91.069 / 90.982 | 90.728 / 90.637 | 87.818 / 87.652 |
| sieve 10000000 | 3.068 / 3.097 | 3.014 / 3.210 | 3.281 / 3.062 | 350.984 / 342.433 | 294.758 / 294.566 | 331.731 / 326.772 | 333.871 / 334.812 |
| init 0 | 8.722 / 8.657 | 8.695 / 8.585 | 8.606 / 8.558 | 552.064 / 553.811 | 357.357 / 352.123 | 351.779 / 348.952 | 626.337 / 629.100 |
| tick 0 | 8.584 / 8.538 | 8.607 / 8.528 | 8.668 / 8.590 | 65.081 / 64.166 | 65.347 / 64.648 | 65.410 / 63.908 | 40.224 / 40.217 |

Retained core construction and reused lifecycle; these are not public-call ratios

| Case | Facts constructor | Memory/frame constructor | Reused reset | Reused call | Reused publication | Reused total |
|---|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 2.659 / 2.711 | 0.541 / 0.525 | 0.048 / 0.048 | 3.198 / 3.222 | 0.015 / 0.013 | 3.262 / 3.283 |
| minimal 100000 | 0.012 / 0.013 | 0.066 / 0.061 | 0.002 / 0.002 | 6.080 / 6.091 | 0.002 / 0.002 | 6.083 / 6.096 |
| memset 100000 | 0.056 / 0.056 | 3.549 / 3.199 | 0.229 / 0.193 | 3.621 / 3.621 | 0.069 / 0.060 | 3.913 / 3.876 |
| pinky 1 | 0.841 / 0.845 | 0.435 / 0.420 | 0.032 / 0.032 | 86.747 / 86.765 | 0.149 / 0.148 | 86.924 / 86.944 |
| sieve 10000000 | 2.810 / 2.680 | 0.552 / 0.544 | 0.062 / 0.053 | 325.933 / 328.264 | 0.296 / 0.284 | 326.285 / 328.607 |
| init 0 | 8.647 / 8.605 | 14.001 / 14.224 | 7.212 / 6.971 | 338.884 / 332.245 | 0.039 / 0.033 | 346.136 / 339.231 |
| tick 0 | 8.579 / 8.552 | 14.084 / 13.992 | 6.315 / 6.184 | 41.816 / 41.662 | 0.036 / 0.035 | 48.171 / 47.913 |

Reference DOOM invocation lifecycle; module construction remains separate

| Case | Restore | Call | Teardown | Total |
|---|---:|---:|---:|---:|
| init | 2.729 / 2.627 | 628.088 / 625.142 | 0.329 / 0.308 | 631.129 / 628.107 |
| tick | 2.449 / 2.469 | 40.130 / 40.093 | 0.147 / 0.123 | 42.757 / 42.679 |

Current public native totals across all thirteen calls; source attempts are per retained-core call, not hardware instructions

| Case | Publications | Native calls | Lowered operations | Code used bytes | Conditional calls | Whole-header calls | Compilation CPU | Source attempts/call |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 723 / 723 | 2,699,169 / 2,699,169 | 12,479,481 / 12,479,481 | 340,444 / 340,444 | 1,970,793 / 1,970,793 | 1,952,516 / 1,952,516 | 1.678 / 1.698 | 1,166,742 / 1,166,742 |
| minimal 100000 | 5 / 5 | 1,300,039 / 1,300,039 | 5,200,129 / 5,200,129 | 880 / 880 | 12 / 12 | 0 / 0 | 0.078 / 0.075 | 2,000,035 / 2,000,035 |
| memset 100000 | 54 / 54 | 3,900,351 / 3,900,351 | 9,101,412 / 9,101,412 | 5,488 / 5,488 | 3,900,151 / 3,900,151 | 1,300,084 / 1,300,084 | 0.198 / 0.195 | 1,200,349 / 1,200,349 |
| pinky 1 | 606 / 606 | 36,282,987 / 36,282,987 | 184,616,372 / 184,616,372 | 70,120 / 70,120 | 21,030,287 / 21,030,287 | 13,669,609 / 13,669,609 | 1.047 / 1.043 | 32,055,270 / 32,055,270 |
| sieve 10000000 | 750 / 750 | 271,619,743 / 271,619,743 | 1,250,782,976 / 1,250,782,976 | 345,768 / 345,768 | 199,590,176 / 199,590,176 | 195,021,015 / 195,021,015 | 1.805 / 1.779 | 123,322,753 / 123,322,753 |
| init 0 | 1,017 / 1,017 | 14,936,389 / 14,936,389 | 2,272,367,823 / 2,272,367,823 | 130,604 / 130,604 | 7,243,063 / 7,243,063 | 4,205,022 / 4,205,022 | 5.503 / 5.460 | 203,298,231 / 203,298,231 |
| tick 0 | 887 / 887 | 24,869,221 / 24,869,221 | 93,369,909 / 93,369,909 | 123,572 / 123,572 | 20,525,709 / 20,525,709 | 1,809,870 / 1,809,870 | 1.620 / 1.622 | 15,523,334 / 15,523,334 |


## x86 unchanged-path control

Separate native x86 runner: AMD EPYC 9V74 80-Core Processor. No ARM/x86 paired ratio is claimed.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.385 / 3.502 | 2.683 / 2.735 | 2.646 / 2.689 | 2.520 / 2.517 | 5.251 / 4.942 | 0.782 / 0.768 | 0.504 / 0.544 |
| minimal 100000 | 5.453 / 5.161 | 5.086 / 5.094 | 5.011 / 5.119 | 5.090 / 5.156 | 6.268 / 6.201 | 0.919 / 0.992 | 0.799 / 0.826 |
| memset 100000 | 3.585 / 4.225 | 3.569 / 4.044 | 3.857 / 4.143 | 3.011 / 2.914 | 3.895 / 3.850 | 1.076 / 0.981 | 0.990 / 1.076 |
| pinky 1 | 91.083 / 92.303 | 79.928 / 80.354 | 79.840 / 79.344 | 78.470 / 78.990 | 101.550 / 104.700 | 0.877 / 0.860 | 0.786 / 0.758 |
| sieve 10000000 | 327.200 / 318.270 | 268.363 / 268.956 | 264.168 / 264.131 | 262.133 / 262.917 | 394.846 / 396.840 | 0.807 / 0.830 | 0.669 / 0.666 |
| init 0 | 423.447 / 423.181 | 421.002 / 422.741 | 417.883 / 421.077 | 406.172 / 404.402 | 619.334 / 672.947 | 0.987 / 0.995 | 0.675 / 0.626 |
| tick 0 | 47.306 / 49.641 | 48.252 / 46.322 | 47.691 / 47.629 | 41.155 / 39.942 | 44.838 / 45.142 | 1.008 / 0.959 | 1.064 / 1.055 |

All following CPU values are milliseconds, forward / reverse. Constructors and cold calls are separate from reused calls.

Public owner construction and cold sample zero

| Case | Interpreter owner | Previous owner | Current owner | Interpreter cold | Previous cold | Current cold | Reference cold call |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.123 / 3.108 | 3.360 / 3.128 | 3.348 / 3.408 | 8.729 / 8.777 | 9.936 / 10.791 | 9.833 / 10.509 | 5.471 / 5.206 |
| minimal 100000 | 0.016 / 0.016 | 0.021 / 0.019 | 0.016 / 0.016 | 5.355 / 5.132 | 5.157 / 5.203 | 5.191 / 5.166 | 6.197 / 6.232 |
| memset 100000 | 0.073 / 0.057 | 0.060 / 0.059 | 0.056 / 0.071 | 10.716 / 8.900 | 10.839 / 9.032 | 10.552 / 10.965 | 4.011 / 3.977 |
| pinky 1 | 0.721 / 0.726 | 0.694 / 0.752 | 0.730 / 0.725 | 93.938 / 94.198 | 85.130 / 85.460 | 84.994 / 84.783 | 104.057 / 102.078 |
| sieve 10000000 | 3.503 / 3.247 | 3.102 / 3.128 | 3.520 / 3.388 | 330.470 / 324.443 | 275.022 / 275.925 | 270.799 / 271.494 | 390.998 / 394.696 |
| init 0 | 8.460 / 8.575 | 8.477 / 8.539 | 8.404 / 11.356 | 451.721 / 449.214 | 459.288 / 463.077 | 461.284 / 466.775 | 621.424 / 675.389 |
| tick 0 | 8.546 / 11.165 | 8.524 / 8.578 | 8.628 / 8.539 | 70.409 / 78.185 | 73.149 / 71.973 | 71.730 / 72.108 | 47.671 / 47.615 |

Retained core construction and reused lifecycle; these are not public-call ratios

| Case | Facts constructor | Memory/frame constructor | Reused reset | Reused call | Reused publication | Reused total |
|---|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 2.527 / 2.782 | 0.571 / 0.564 | 0.035 / 0.048 | 2.520 / 2.517 | 0.008 / 0.015 | 2.565 / 2.580 |
| minimal 100000 | 0.012 / 0.012 | 0.083 / 0.082 | 0.003 / 0.003 | 5.090 / 5.156 | 0.003 / 0.003 | 5.100 / 5.168 |
| memset 100000 | 0.056 / 0.058 | 3.933 / 4.109 | 0.147 / 0.272 | 3.011 / 2.914 | 0.036 / 0.058 | 3.197 / 3.252 |
| pinky 1 | 0.860 / 0.836 | 0.454 / 0.446 | 0.023 / 0.024 | 78.470 / 78.990 | 0.140 / 0.146 | 78.634 / 79.171 |
| sieve 10000000 | 3.344 / 2.721 | 0.263 / 0.499 | 0.038 / 0.045 | 262.133 / 262.917 | 0.290 / 0.304 | 262.461 / 263.274 |
| init 0 | 8.506 / 8.626 | 17.065 / 17.523 | 5.766 / 5.975 | 406.172 / 404.402 | 0.013 / 0.021 | 411.483 / 410.604 |
| tick 0 | 8.571 / 8.588 | 17.484 / 17.509 | 4.967 / 4.776 | 41.155 / 39.942 | 0.022 / 0.023 | 46.191 / 45.187 |

Reference DOOM invocation lifecycle; module construction remains separate

| Case | Restore | Call | Teardown | Total |
|---|---:|---:|---:|---:|
| init | 7.818 / 8.083 | 619.334 / 672.947 | 1.299 / 1.300 | 628.510 / 682.344 |
| tick | 8.062 / 7.892 | 44.838 / 45.142 | 1.312 / 1.108 | 54.759 / 54.183 |

Current public native totals across all thirteen calls; source attempts are per retained-core call, not hardware instructions

| Case | Publications | Native calls | Lowered operations | Code used bytes | Conditional calls | Whole-header calls | Compilation CPU | Source attempts/call |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 184 / 184 | 1,962,277 / 1,962,277 | 9,156,925 / 9,156,925 | 21,663 / 21,663 | 1,952,564 / 1,952,564 | 1,952,516 / 1,952,516 | 1.306 / 1.410 | 1,166,742 / 1,166,742 |
| minimal 100000 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0.015 / 0.015 | 2,000,035 / 2,000,035 |
| memset 100000 | 31 / 31 | 1,300,208 / 1,300,208 | 3,900,859 / 3,900,859 | 2,212 / 2,212 | 1,300,118 / 1,300,118 | 1,300,084 / 1,300,084 | 0.184 / 0.182 | 1,200,349 / 1,200,349 |
| pinky 1 | 335 / 335 | 28,051,881 / 28,051,881 | 156,172,295 / 156,172,295 | 37,060 / 37,060 | 17,569,870 / 17,569,870 | 13,669,609 / 13,669,609 | 1.339 / 1.256 | 32,055,270 / 32,055,270 |
| sieve 10000000 | 184 / 184 | 195,560,110 / 195,560,110 | 912,289,194 / 912,289,194 | 21,663 / 21,663 | 195,021,063 / 195,021,063 | 195,021,015 / 195,021,015 | 1.385 / 1.402 | 123,322,753 / 123,322,753 |
| init 0 | 1,024 / 1,024 | 13,957,895 / 13,957,895 | 62,653,474 / 62,653,474 | 94,821 / 94,821 | 7,246,021 / 7,246,021 | 6,377,171 / 6,377,171 | 6.673 / 6.622 | 203,298,231 / 203,298,231 |
| tick 0 | 462 / 462 | 5,674,903 / 5,674,903 | 21,853,912 / 21,853,912 | 41,648 / 41,648 | 1,815,881 / 1,815,881 | 1,809,870 / 1,809,870 | 1.917 / 1.913 | 15,523,334 / 15,523,334 |


## Restoration qualification

The final feature layer's production, native, tests, tooling, build and workflow trees are
byte-for-byte identical to parent14105fe3d85be32dc98c9f6a584ef9dd903f0a99. Only this evidence
file remains as a new tracked file. The exact parent runtime and witnesses retain their previous
native qualification (including40716027277 and the accepted x86 cohorts); the candidate's new
witnesses passed in40727783535 but are historical evidence, not claims about retained capacity.
Use tree equality and prior covered results rather than rerunning unchanged native sources.
The final documentation commit is not the measured head. Nothing was merged or enabled.
