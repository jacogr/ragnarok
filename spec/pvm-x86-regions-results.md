# Connected x86 region measurements

Provisional positive sieve result; retain the isolated runtime pending the second complete
cohort and ARM qualification. No merge or new public default is included.

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
