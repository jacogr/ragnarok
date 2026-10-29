# Connected x86 region measurements

Verdict: retain the isolated connected-loop runtime after four qualified paired cohorts and
bounded fresh-process validation. Claim stable gains on sieve only; do not infer a universal
speedup or a hardware cause for process outliers. The PR remains draft in the independent
experimental stack; no merge or public engine-policy change is included.

[CI40707383145](https://github.com/jacogr/ragnarok/actions/runs/40707383145) passes at
`08aca203230cd31919335fe5430bb8d50eff6091` against pinned parent
`f45793f6bfe92d38488b52898652e5dfb49ddbdb`, Intel Xeon Platinum8573C. Compiler remains
October26 Nimony358b9bce with checked release/ARC/Clang ThinLTO. All thirteen native/refusal,
complete-state, memory/host and exclusive-ownership gates pass, including1440 new one/two-block
region-prefix cases per native/refused witness. Independent audits reparse all native logs and
verify485 native source/compiler identities.

The application cohort passes70 measured processes /910 checked calls,115 positive/refusal
controls,16 fresh builds/eight equal-image pairs and745 recorded identities. Independent source,
compiler/input/image and raw process/control audits pass; complete gas/register/page/permission/
source snapshots and ordered host-event checks are retained. Application report SHA256:
`7e37ee69d197c4da7834d2923e5eec85dca029d9abe3bf7a5f95506067caa7ec`.
Native qualification report SHA256:
`9f2eaac54c144ba26a7409ef1f3e61f5db128a1a570f5cc310d9edf6902e065c`.

Short sieve improves9.2–9.4% and long sieve11.6% against the paired JIT parent in both process
orders. Native calls halve with identical lowered-operation totals: short3,912,233 to1,962,277;
long390,560,066 to195,560,110 across thirteen calls. One extra region uses272 additional code
bytes. Arithmetic still uses its existing register-array loads/stores; this trial isolates
connected control, native gas/source guards and handoff reduction.

Tradeoffs: minimal has zero native leaves and regresses about3.4%; fill moves0.6–1.8% slower.
Pinky stays within1%. Gameplay timing moves favorably but has identical native activity, so it
is not attributed to region execution. Initialization still reaches1024 publications. Cold Pinky
has a forward outlier126.968ms versus85.456ms parent, while reverse83.886ms versus85.343ms does
not reproduce it. The next complete cohort must check this before any broad readiness verdict.
Cold short sieve improves11.256/11.148 to10.126/9.995ms, but still exceeds interpretation.
No cross-runner paired ratios or claims about ARM performance are made.

All six exact-head scoped profiles pass calibrated selected/absent/repeated/last-return controls,
raw cold/final-reused hashes, self-cost sums equal to raw totals, thirteen complete state-checked
calls and matching uninstrumented native activity. Instrumented clocks are discarded.

| Scope | Policy | Reused native instructions (Ir) | Conditional simulated misses | Indirect simulated misses |
|---|---|---:|---:|---:|
| Sieve100k | Interpreter |43,530,941|12,916|767,824|
| Sieve100k | Current JIT |42,520,938|13,056|466,286|
| Pinky | Interpreter |1,164,383,002|1,737,762|28,804,895|
| Pinky | Current JIT |1,086,911,692|1,991,980|21,176,046|
| DOOM gameplay | Interpreter |587,244,205|355,155|11,745,415|
| DOOM gameplay | Current JIT |583,996,033|399,381|11,339,588|

Simulated misses are not hardware measurements; instruction counts alone do not explain CPU time.
For sieve, flatX86Region and callX86Region still account for6.25m and5.05m self Ir per reused call.
Their metadata/context validation and accounting are future bounded targets; no such change is
mixed into this trial. Pinky/gameplay profiles remain dominated by checked charging, dispatch and
memory. A larger or memory-capable region needs separate proofs and measurements.

The complete paired lifecycle tables follow. Public call includes fresh invocation memory and
immutable publication. Owner construction, core reset/publication and reference restoration/
teardown remain separate; cold samples are not reused medians.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.277 / 3.274 | 2.623 / 2.616 | 2.382 / 2.370 | 1.986 / 1.986 | 4.550 / 4.528 | 0.727 / 0.724 | 0.524 / 0.523 |
| minimal 100000 | 5.183 / 5.207 | 5.005 / 5.006 | 5.174 / 5.180 | 4.929 / 4.927 | 4.860 / 4.862 | 0.998 / 0.995 | 1.065 / 1.065 |
| memset 100000 | 4.399 / 4.440 | 3.791 / 3.833 | 3.859 / 3.857 | 2.599 / 2.625 | 3.582 / 3.585 | 0.877 / 0.869 | 1.077 / 1.076 |
| pinky 1 | 97.085 / 95.225 | 80.496 / 80.391 | 80.294 / 79.926 | 77.544 / 77.078 | 92.679 / 90.948 | 0.827 / 0.839 | 0.866 / 0.879 |
| sieve 10000000 | 308.428 / 310.246 | 244.579 / 244.816 | 216.243 / 216.396 | 205.800 / 205.450 | 326.765 / 327.007 | 0.701 / 0.697 | 0.662 / 0.662 |
| init 0 | 377.999 / 377.584 | 378.174 / 375.370 | 374.982 / 374.747 | 365.406 / 369.983 | 593.452 / 590.545 | 0.992 / 0.992 | 0.632 / 0.635 |
| tick 0 | 40.259 / 40.365 | 41.632 / 40.610 | 39.806 / 37.975 | 31.443 / 31.331 | 31.737 / 31.752 | 0.989 / 0.941 | 1.254 / 1.196 |

All following CPU values are milliseconds, forward / reverse. Constructors and cold calls are separate from reused calls.

Public owner construction and cold sample zero

| Case | Interpreter owner | Previous owner | Current owner | Interpreter cold | Previous cold | Current cold | Reference cold call |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.353 / 3.288 | 3.368 / 3.329 | 3.332 / 3.289 | 9.516 / 9.407 | 11.256 / 11.148 | 10.126 / 9.995 | 4.832 / 4.818 |
| minimal 100000 | 0.021 / 0.018 | 0.018 / 0.015 | 0.054 / 0.017 | 5.393 / 5.300 | 5.171 / 5.187 | 5.311 / 5.366 | 4.948 / 5.277 |
| memset 100000 | 0.058 / 0.070 | 0.059 / 0.071 | 0.059 / 0.057 | 10.848 / 10.531 | 9.076 / 10.594 | 10.626 / 8.980 | 3.695 / 3.728 |
| pinky 1 | 0.794 / 0.816 | 0.758 / 0.760 | 0.744 / 0.756 | 98.917 / 113.969 | 85.456 / 85.343 | 126.968 / 83.886 | 92.302 / 90.922 |
| sieve 10000000 | 3.686 / 3.445 | 3.338 / 3.342 | 3.368 / 3.282 | 315.179 / 314.905 | 251.764 / 253.817 | 224.359 / 225.401 | 325.371 / 325.303 |
| init 0 | 9.855 / 12.399 | 13.518 / 10.005 | 9.926 / 10.134 | 402.962 / 410.935 | 416.312 / 406.894 | 406.615 / 407.793 | 589.181 / 590.696 |
| tick 0 | 9.818 / 9.862 | 13.220 / 10.015 | 13.128 / 9.842 | 61.098 / 61.512 | 72.782 / 62.767 | 65.643 / 61.505 | 32.532 / 32.440 |

Retained core construction and reused lifecycle; these are not public-call ratios

| Case | Facts constructor | Memory/frame constructor | Reused reset | Reused call | Reused publication | Reused total |
|---|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 2.929 / 2.887 | 0.705 / 0.778 | 0.074 / 0.074 | 1.986 / 1.986 | 0.009 / 0.009 | 2.072 / 2.073 |
| minimal 100000 | 0.011 / 0.016 | 0.082 / 0.089 | 0.003 / 0.003 | 4.929 / 4.927 | 0.002 / 0.002 | 4.935 / 4.932 |
| memset 100000 | 0.068 / 0.068 | 4.607 / 4.367 | 0.303 / 0.302 | 2.599 / 2.625 | 0.040 / 0.051 | 2.941 / 2.983 |
| pinky 1 | 0.740 / 0.889 | 0.697 / 0.521 | 0.038 / 0.036 | 77.544 / 77.078 | 0.149 / 0.150 | 77.725 / 77.259 |
| sieve 10000000 | 3.186 / 2.889 | 0.730 / 0.727 | 0.096 / 0.096 | 205.800 / 205.450 | 0.368 / 0.393 | 206.251 / 205.967 |
| init 0 | 9.968 / 10.525 | 17.852 / 18.603 | 9.295 / 9.674 | 365.406 / 369.983 | 0.025 / 0.028 | 374.679 / 379.892 |
| tick 0 | 10.080 / 13.210 | 17.981 / 19.938 | 8.475 / 8.539 | 31.443 / 31.331 | 0.030 / 0.029 | 40.023 / 40.014 |

Reference DOOM invocation lifecycle; module construction remains separate

| Case | Restore | Call | Teardown | Total |
|---|---:|---:|---:|---:|
| init | 10.284 / 10.545 | 593.452 / 590.545 | 0.773 / 0.817 | 604.428 / 602.175 |
| tick | 8.417 / 7.871 | 31.737 / 31.752 | 0.619 / 0.585 | 41.183 / 40.357 |

Current public native totals across all thirteen calls; source attempts are per retained-core call, not hardware instructions

| Case | Publications | Native calls | Lowered operations | Code used bytes | Conditional calls | Whole-header calls | Compilation CPU | Source attempts/call |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 184 / 184 | 1,962,277 / 1,962,277 | 9,156,925 / 9,156,925 | 21,663 / 21,663 | 1,952,564 / 1,952,564 | 1,952,516 / 1,952,516 | 1.075 / 1.046 | 1,166,742 / 1,166,742 |
| minimal 100000 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0.010 / 0.011 | 2,000,035 / 2,000,035 |
| memset 100000 | 31 / 31 | 1,300,208 / 1,300,208 | 3,900,859 / 3,900,859 | 2,212 / 2,212 | 1,300,118 / 1,300,118 | 1,300,084 / 1,300,084 | 0.124 / 0.124 | 1,200,349 / 1,200,349 |
| pinky 1 | 335 / 335 | 28,051,881 / 28,051,881 | 156,172,295 / 156,172,295 | 37,060 / 37,060 | 17,569,870 / 17,569,870 | 13,669,609 / 13,669,609 | 0.915 / 0.873 | 32,055,270 / 32,055,270 |
| sieve 10000000 | 184 / 184 | 195,560,110 / 195,560,110 | 912,289,194 / 912,289,194 | 21,663 / 21,663 | 195,021,063 / 195,021,063 | 195,021,015 / 195,021,015 | 1.239 / 1.125 | 123,322,753 / 123,322,753 |
| init 0 | 1,024 / 1,024 | 13,957,895 / 13,957,895 | 62,653,474 / 62,653,474 | 94,821 / 94,821 | 7,246,021 / 7,246,021 | 6,377,171 / 6,377,171 | 3.898 / 3.981 | 203,298,231 / 203,298,231 |
| tick 0 | 462 / 462 | 5,674,903 / 5,674,903 | 21,853,912 / 21,853,912 | 41,648 / 41,648 | 1,815,881 / 1,815,881 | 1,809,870 / 1,809,870 | 1.162 / 1.137 | 15,523,334 / 15,523,334 |


## Final paired and process-replication verdict

Four qualified complete cohorts preserve the sieve benefit, each compared only with its own
pinned parent on the same runner: run40707383145 on Xeon8573C; run40712609291 on EPYC9V74;
run40716027277 on EPYC9V45; and
[run40718101383](https://github.com/jacogr/ragnarok/actions/runs/40718101383) on EPYC7763.
These are separate machine cohorts, not samples to combine into one paired CPU ratio.
Within-cohort short-sieve gains span about9–15% and long-sieve gains12–18% across both orders.
No new register allocator or memory lowering was introduced.

The final measured head is `79deafbf5221d96902829821e57822693aea711b`, with the same parent
`f45793f6bfe92d38488b52898652e5dfb49ddbdb` and compiler pin. Runtime, native witnesses and
benchmark drivers remain byte-identical to the first qualified08aca203 head. The final head
adds replay-only tooling, manual workflow routing, pure tests and documentation. All thirteen
native/refusal/ownership gates pass again with independent485-identity/native-log audit.

The ordinary70-process /910-call cohort and115 controls pass with16 builds/eight equal-image
pairs and746 independently audited source/input/compiler/image identities. It additionally runs
36 fresh processes /468 checked calls, six processes per role/case across init/minimal/Pinky,
with balanced relative order. Every raw replay log reparses identically and matches its original
native calls/operations/code footprint except compilation CPU. Total:106 measured processes /
1378 checked calls. No native execution or profiling was performed locally.
Application report SHA256:
`2ad654b1fd0dbb96738ff9c119082f6edef5805d9de7432c9227752fb1532acf`.
Native qualification report SHA256:
`b863848829a5f5ef6de57fd685c260e5efb1fd2847d65d66e46d6da6285e9cde`.

Initialization process medians overlap: parent568.269ms (563.328–572.720) versus current569.989ms
(558.553–572.081), about0.3% median difference. No systematic initialization loss is demonstrated
in these six processes per version. Minimal current6.708ms versus parent6.912ms and Pinky128.482ms
versus129.703ms likewise show no systematic loss, but are not claimed as region gains.
Earlier whole-process outliers occurred in both parent and current images across cohorts; all
are retained, including a11.316ms current minimal primary sample median in the final cohort.
This replication neither removes those observations nor identifies their CPU-level cause.

Keep the useful sieve change with these qualifications. Ordinary public memory construction,
immutable publication and unsupported checked execution still dominate several workloads.
Initialization's1024 publications and the stream's single-region policy remain explicit limits.
Future work is separately bounded: reduce proven region-wrapper metadata costs, investigate
larger/memory-capable regions, and avoid first-admitted-region starvation. Background compilation
would address preparation latency rather than these remaining warm execution boundaries.

Latest primary and fresh-process tables follow. These CPUms are all from the final EPYC7763
runner. Primary forward/reverse values and replay distributions are different sample scopes;
no replay median is paired with a reference measurement from another scope.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 4.059 / 4.033 | 4.061 / 3.960 | 3.515 / 3.365 | 3.212 / 3.197 | 6.065 / 6.040 | 0.866 / 0.834 | 0.580 / 0.557 |
| minimal 100000 | 6.639 / 6.493 | 7.067 / 7.071 | 6.514 / 11.316 | 6.565 / 6.585 | 7.463 / 7.476 | 0.981 / 1.743 | 0.873 / 1.514 |
| memset 100000 | 5.259 / 5.066 | 5.224 / 5.074 | 5.215 / 4.875 | 3.653 / 3.507 | 4.180 / 4.181 | 0.992 / 0.962 | 1.248 / 1.166 |
| pinky 1 | 158.737 / 157.284 | 128.227 / 131.791 | 137.295 / 129.546 | 129.405 / 128.679 | 185.536 / 189.023 | 0.865 / 0.824 | 0.740 / 0.685 |
| sieve 10000000 | 384.634 / 390.567 | 387.987 / 395.589 | 325.225 / 324.173 | 339.566 / 339.665 | 446.299 / 445.395 | 0.846 / 0.830 | 0.729 / 0.728 |
| init 0 | 573.589 / 575.327 | 739.844 / 559.428 | 569.260 / 576.523 | 566.382 / 567.019 | 774.702 / 777.483 | 0.992 / 1.002 | 0.735 / 0.742 |
| tick 0 | 56.942 / 59.850 | 54.134 / 58.214 | 57.865 / 57.316 | 48.301 / 48.797 | 53.778 / 52.486 | 1.016 / 0.958 | 1.076 / 1.092 |

All following CPU values are milliseconds, forward / reverse. Constructors and cold calls are separate from reused calls.

Public owner construction and cold sample zero

| Case | Interpreter owner | Previous owner | Current owner | Interpreter cold | Previous cold | Current cold | Reference cold call |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.822 / 3.748 | 3.837 / 3.763 | 3.852 / 4.042 | 10.683 / 10.556 | 13.810 / 13.733 | 12.763 / 11.962 | 6.265 / 6.297 |
| minimal 100000 | 0.022 / 0.018 | 0.018 / 0.018 | 0.016 / 0.022 | 6.855 / 6.894 | 7.248 / 7.224 | 6.921 / 6.903 | 7.589 / 7.610 |
| memset 100000 | 0.067 / 0.070 | 0.068 / 0.069 | 0.066 / 0.067 | 10.286 / 12.424 | 10.418 / 12.423 | 10.338 / 12.475 | 4.353 / 4.653 |
| pinky 1 | 0.874 / 0.894 | 0.887 / 0.890 | 0.878 / 1.040 | 176.884 / 174.598 | 147.643 / 145.409 | 146.780 / 139.004 | 193.904 / 192.851 |
| sieve 10000000 | 4.143 / 4.022 | 3.956 / 4.003 | 4.066 / 3.870 | 392.608 / 397.266 | 395.435 / 397.996 | 330.013 / 331.012 | 451.110 / 445.018 |
| init 0 | 10.959 / 11.267 | 14.240 / 11.577 | 11.252 / 11.244 | 605.540 / 607.583 | 784.794 / 602.823 | 609.353 / 617.757 | 761.594 / 757.714 |
| tick 0 | 11.108 / 11.297 | 11.317 / 11.522 | 11.266 / 11.121 | 81.904 / 82.396 | 86.872 / 85.132 | 82.682 / 85.250 | 54.028 / 55.244 |

Retained core construction and reused lifecycle; these are not public-call ratios

| Case | Facts constructor | Memory/frame constructor | Reused reset | Reused call | Reused publication | Reused total |
|---|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.137 / 3.369 | 0.648 / 0.661 | 0.066 / 0.061 | 3.212 / 3.197 | 0.012 / 0.011 | 3.289 / 3.270 |
| minimal 100000 | 0.013 / 0.014 | 0.094 / 0.095 | 0.003 / 0.004 | 6.565 / 6.585 | 0.003 / 0.003 | 6.571 / 6.596 |
| memset 100000 | 0.068 / 0.070 | 4.555 / 5.092 | 0.482 / 0.350 | 3.653 / 3.507 | 0.063 / 0.051 | 4.197 / 3.910 |
| pinky 1 | 1.064 / 1.039 | 0.548 / 0.517 | 0.050 / 0.043 | 129.405 / 128.679 | 0.176 / 0.188 | 129.638 / 128.899 |
| sieve 10000000 | 3.355 / 3.194 | 0.603 / 0.742 | 0.058 / 0.078 | 339.566 / 339.665 | 0.366 / 0.362 | 339.939 / 340.131 |
| init 0 | 11.461 / 11.638 | 19.776 / 19.861 | 8.189 / 7.693 | 566.382 / 567.019 | 0.025 / 0.026 | 574.039 / 574.418 |
| tick 0 | 11.468 / 14.866 | 19.449 / 23.130 | 6.801 / 6.962 | 48.301 / 48.797 | 0.025 / 0.025 | 55.525 / 55.743 |

Reference DOOM invocation lifecycle; module construction remains separate

| Case | Restore | Call | Teardown | Total |
|---|---:|---:|---:|---:|
| init | 10.195 / 10.368 | 774.702 / 777.483 | 1.602 / 1.613 | 786.513 / 789.377 |
| tick | 10.132 / 10.508 | 53.778 / 52.486 | 1.214 / 1.474 | 65.117 / 64.487 |

Current public native totals across all thirteen calls; source attempts are per retained-core call, not hardware instructions

| Case | Publications | Native calls | Lowered operations | Code used bytes | Conditional calls | Whole-header calls | Compilation CPU | Source attempts/call |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 184 / 184 | 1,962,277 / 1,962,277 | 9,156,925 / 9,156,925 | 21,663 / 21,663 | 1,952,564 / 1,952,564 | 1,952,516 / 1,952,516 | 1.690 / 1.521 | 1,166,742 / 1,166,742 |
| minimal 100000 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0.014 / 0.015 | 2,000,035 / 2,000,035 |
| memset 100000 | 31 / 31 | 1,300,208 / 1,300,208 | 3,900,859 / 3,900,859 | 2,212 / 2,212 | 1,300,118 / 1,300,118 | 1,300,084 / 1,300,084 | 0.190 / 0.198 | 1,200,349 / 1,200,349 |
| pinky 1 | 335 / 335 | 28,051,881 / 28,051,881 | 156,172,295 / 156,172,295 | 37,060 / 37,060 | 17,569,870 / 17,569,870 | 13,669,609 / 13,669,609 | 1.487 / 1.505 | 32,055,270 / 32,055,270 |
| sieve 10000000 | 184 / 184 | 195,560,110 / 195,560,110 | 912,289,194 / 912,289,194 | 21,663 / 21,663 | 195,021,063 / 195,021,063 | 195,021,015 / 195,021,015 | 1.553 / 1.739 | 123,322,753 / 123,322,753 |
| init 0 | 1,024 / 1,024 | 13,957,895 / 13,957,895 | 62,653,474 / 62,653,474 | 94,821 / 94,821 | 7,246,021 / 7,246,021 | 6,377,171 / 6,377,171 | 7.160 / 7.200 | 203,298,231 / 203,298,231 |
| tick 0 | 462 / 462 | 5,674,903 / 5,674,903 | 21,853,912 / 21,853,912 | 41,648 / 41,648 | 1,815,881 / 1,815,881 | 1,809,870 / 1,809,870 | 2.084 / 2.103 | 15,523,334 / 15,523,334 |

Fresh-process replication: six processes per role/case, thirteen checked calls each.
CPU milliseconds: median across process medians, with minimum / maximum; owner and cold are separate.

| Case | Role | Owner median | Cold median | Reused median | Reused min / max |
|---|---|---:|---:|---:|---:|
| init | baseline | 12.819 | 610.189 | 568.269 | 563.328 / 572.720 |
| init | jit | 11.053 | 611.324 | 569.989 | 558.553 / 572.081 |
| minimal | baseline | 0.018 | 7.079 | 6.912 | 6.859 / 7.210 |
| minimal | jit | 0.021 | 6.897 | 6.708 | 6.624 / 6.826 |
| pinky | baseline | 0.892 | 139.848 | 129.703 | 129.274 / 132.339 |
| pinky | jit | 0.883 | 139.650 | 128.482 | 127.334 / 130.171 |
