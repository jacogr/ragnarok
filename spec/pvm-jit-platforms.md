# Native JIT default build selection

Scope: select the existing independent emitter in ordinary peer builds on the maintained host
matrix. The Gray Paper, `pvm-execution`, `pvm-handler-stream` and `pvm-x86-jit` semantics remain
unchanged. There is no new evaluator, public engine identity or toolchain/dependency upgrade.

| Host | Native build define |
|---|---|
| Linux x86-64 | `pvmX86Jit` |
| Linux ARM64 | `pvmArm64Jit` |
| macOS ARM64 | `pvmArm64Jit` |
| Other OS/CPU pairs | Neither; checked interpreter fallback |

The public default was already `jit`; the production builder now includes the corresponding
backend using the same pure `native_defines` plan as the real CLI comparison driver. Explicit
`--pvm-backend interpreted` disables native preparation/execution. Unsupported operations,
partial budgets and executable-storage refusal keep checked same-engine fallback. Optional
PolkaVM engines retain their explicit independent selection and do not substitute silently.
Library consumers still select their desired native compile define explicitly.

Ordinary native Linux CI runs the corresponding x86/ARM positive/refusal, opcode, memory/host,
source-prefix and ownership gates. Existing ARM-only public-policy tests additionally retain
an unavailable-backend control on x86; the x86-specific qualification runs positive and refused
public policies with its genuine native flag. The PVM Comparison job uses public JIT/interpreter
application cohorts on both Linux architectures. Baseline receipts record a controlled matching
native build where the source provides that backend, and checked fallback for older x86 sources;
this is not a claim that an opt-in historical backend was that revision's shipped default.

Real CLI-selected continuing DOOM parity must prove native execution on both supported Linux
architectures and match PolkaVM interpreted frame bytes/hashes, complete state/gas and ordered
host events. Existing mutation/refusal controls remain required. All native compilation,
execution, performance and profiling stay on CI during this work.

Status: qualified for review as the maintained-host default. Native platform gates, real
continuing-frame parity, production builds and the ordinary two-architecture comparison pass
with the provenance below. Explicit interpreted selection and checked fallback remain available.
No PR merge is authorized.


## Exact-head production and continuing-frame qualification

[Run40691521892](https://github.com/jacogr/ragnarok/actions/runs/40691521892) at
`0031e64cdd6066f56471011303d4bf647605c1ec` passes real CLI-selected continuing DOOM on both
native Linux architectures. Both calls report actual `jit`, with positive compilation/execution
counters and supported native flags. All state, gas, ordered host-event and RGBA hashes match
PolkaVM interpreted, and the same two distinct frame hashes match across both architectures.
Six mutation/refusal controls pass per architecture. Independent source/build/raw-log audits
verify the exact compiler pin, expected native define and recorded outputs.

Frame RGBA SHA256 values:

- `44f42f5bed248db9caadf2caf329a2857e1c54a084b69d6b44fba83df4e5422b`
- `ce5f398853f8fb00db2e01c84e3248a08bd716ad2dae3fccba3591e64b3e2ce1`

[Run40692892088](https://github.com/jacogr/ragnarok/actions/runs/40692892088) at that same head
passes the real checked production builds, packaging and relocated-peer smoke tests for
Linux/Docker and macOS. Native engine/runtime sources, production flag selection and CLI driver
remain identical after subsequent documentation/report-formatting changes; measured-head
provenance is retained rather than claiming a new executable test from documentation alone.

The ordinary comparison report now retains constructor/cold/reused scopes, retained-core reset
and immutable publication, reference restoration/teardown and software native/source counters.
The formatter has been exercised against seven complete retained cohorts without running native
code locally. The final ordinary two-architecture PVM comparison passes as recorded below.


## Final ordinary comparison and default verdict

[Run40696778945](https://github.com/jacogr/ragnarok/actions/runs/40696778945) passes at
`46ca9b12e842cfc85bf34a185119eea13279234d`, with the unchanged October26 compiler pin
`358b9bce4dd855453f57a80a0c499b0b2e27d7ee`. Each architecture independently completes
70 measured processes /910 checked calls,115 positive/refusal controls,16 fresh builds and
eight equal-image pairs. Source/helper/input/compiler/image identities, complete registers,
gas, pages, permissions, source snapshots and ordered host events pass the retained controls.
Independent audits reparse all process and control logs and verify all736 source identities per
architecture against the recorded revisions. Native qualification passes thirteen x86 gates and
nine ARM gates, plus two public-policy suites on each architecture, with actual supported JIT
availability and checked unavailable-backend behavior. No local native execution was used.

The x86 runner is AMD EPYC9V74. Its controlled previous source is resolved master
`bcbdaf7f0dc1662d33d9727e925be94c0a437f55`, built with the matching optional native flag;
this does not represent that revision's shipped build default. ARM uses the current source for
both JIT image controls, checking the unchanged ARM algorithm and new build/CI routing.
Results are paired only within each runner, never across CPU models or historical runs.

Application receipt SHA256:

- x86: `14e6cd0ca91189038abedc06fbd86ab31dc9d5e869b152066debc856a65bcb06`
- ARM: `f86fde4c13ec1a36f37547a46bde28914a68186bead680dfb43b5ff5f06de7b2`

Verdict: retain the admitted conditional-block model and enable the corresponding native backend
in ordinary maintained-host builds. On x86, reused Pinky improves about12% against the same-source
checked interpreter, short sieve5–6%, long sieve4–5% and gameplay1–2%. Minimal admits no native
leaf and stays within variation. Fill has substantial process-order spread; no precise gain is
claimed. DOOM initialization also has substantial order/outlier spread, so no interpreter-relative
initialization gain is claimed. Cold short sieve costs about2.4ms more than the checked interpreter;
owner construction is separate and remains about3.2ms. Cold costs and fallback coverage remain
limitations rather than grounds for a universal speedup claim.

The x86 public raw call remains2–10% behind the reference on fill and1–5% behind on gameplay.
Reference gameplay restore/call/teardown totals54.684–55.521ms versus our complete public call
46.988–47.380ms; module/owner construction remains separate on both sides. This lifecycle comparison
does not erase the raw-call deficit or imply that a retained-core call is a public invocation.
No hardware counters were collected. Source attempts and native counters describe software work.
Initialization reaches1024 native publications; gameplay uses462. No cache-policy change is included.

Full x86 scopes follow; CPU values are milliseconds, forward / reverse.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.454 / 3.365 | 3.373 / 3.675 | 3.289 / 3.168 | 2.909 / 2.815 | 5.260 / 5.084 | 0.952 / 0.941 | 0.625 / 0.623 |
| minimal 100000 | 5.210 / 5.132 | 5.309 / 5.086 | 5.155 / 5.334 | 4.987 / 4.989 | 6.230 / 6.204 | 0.990 / 1.039 | 0.827 / 0.860 |
| memset 100000 | 5.359 / 4.205 | 4.993 / 4.552 | 4.211 / 3.927 | 2.784 / 2.912 | 3.847 / 3.851 | 0.786 / 0.934 | 1.095 / 1.020 |
| pinky 1 | 91.388 / 91.924 | 94.994 / 93.780 | 79.572 / 81.227 | 78.630 / 78.713 | 102.714 / 103.513 | 0.871 / 0.884 | 0.775 / 0.785 |
| sieve 10000000 | 327.606 / 324.502 | 352.263 / 347.967 | 315.767 / 307.738 | 361.484 / 285.415 | 385.000 / 395.324 | 0.964 / 0.948 | 0.820 / 0.778 |
| init 0 | 416.158 / 555.357 | 431.527 / 430.715 | 465.798 / 413.756 | 411.151 / 407.565 | 676.041 / 625.771 | 1.119 / 0.745 | 0.689 / 0.661 |
| tick 0 | 47.522 / 48.095 | 49.373 / 51.185 | 46.988 / 47.380 | 39.829 / 41.623 | 46.723 / 45.010 | 0.989 / 0.985 | 1.006 / 1.053 |

All following CPU values are milliseconds, forward / reverse. Constructors and cold calls are separate from reused calls.

Public owner construction and cold sample zero

| Case | Interpreter owner | Previous owner | Current owner | Interpreter cold | Previous cold | Current cold | Reference cold call |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.172 / 3.158 | 3.105 / 3.238 | 3.224 / 3.215 | 9.627 / 9.571 | 10.783 / 10.961 | 12.085 / 11.953 | 5.470 / 5.205 |
| minimal 100000 | 0.016 / 0.019 | 0.018 / 0.021 | 0.017 / 0.016 | 5.228 / 5.160 | 5.168 / 5.163 | 5.346 / 5.325 | 6.232 / 6.239 |
| memset 100000 | 0.065 / 0.060 | 0.092 / 0.065 | 0.062 / 0.073 | 9.130 / 11.002 | 11.644 / 9.514 | 11.165 / 10.963 | 3.978 / 3.982 |
| pinky 1 | 0.700 / 0.738 | 0.751 / 0.710 | 0.749 / 0.723 | 96.902 / 95.347 | 99.265 / 96.522 | 84.804 / 86.181 | 103.575 / 104.300 |
| sieve 10000000 | 3.360 / 3.230 | 3.262 / 3.257 | 3.258 / 3.166 | 327.271 / 341.297 | 368.846 / 368.896 | 329.154 / 333.582 | 395.100 / 387.754 |
| init 0 | 8.671 / 8.555 | 8.605 / 8.513 | 8.679 / 11.325 | 444.904 / 583.122 | 470.511 / 462.769 | 504.443 / 459.901 | 621.265 / 675.033 |
| tick 0 | 8.531 / 8.581 | 8.511 / 8.631 | 8.560 / 8.652 | 69.800 / 69.382 | 73.600 / 75.615 | 72.247 / 72.592 | 47.816 / 47.865 |

Retained core construction and reused lifecycle; these are not public-call ratios

| Case | Facts constructor | Memory/frame constructor | Reused reset | Reused call | Reused publication | Reused total |
|---|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 2.740 / 2.569 | 0.528 / 0.532 | 0.043 / 0.042 | 2.909 / 2.815 | 0.013 / 0.014 | 2.967 / 2.874 |
| minimal 100000 | 0.012 / 0.012 | 0.082 / 0.081 | 0.003 / 0.003 | 4.987 / 4.989 | 0.003 / 0.003 | 4.994 / 4.996 |
| memset 100000 | 0.062 / 0.058 | 4.420 / 4.057 | 0.332 / 0.270 | 2.784 / 2.912 | 0.067 / 0.059 | 3.193 / 3.263 |
| pinky 1 | 0.837 / 0.674 | 0.483 / 0.611 | 0.025 / 0.024 | 78.630 / 78.713 | 0.152 / 0.151 | 78.807 / 78.880 |
| sieve 10000000 | 2.623 / 2.538 | 0.618 / 0.532 | 0.056 / 0.044 | 361.484 / 285.415 | 0.324 / 0.297 | 361.825 / 285.802 |
| init 0 | 8.587 / 8.392 | 18.328 / 18.421 | 6.090 / 5.758 | 411.151 / 407.565 | 0.027 / 0.022 | 417.686 / 413.419 |
| tick 0 | 11.071 / 8.446 | 21.018 / 17.927 | 5.019 / 5.069 | 39.829 / 41.623 | 0.021 / 0.022 | 45.242 / 46.628 |

Reference DOOM invocation lifecycle; module construction remains separate

| Case | Restore | Call | Teardown | Total |
|---|---:|---:|---:|---:|
| init | 7.971 / 7.991 | 676.041 / 625.771 | 1.337 / 1.352 | 685.332 / 635.419 |
| tick | 7.850 / 8.031 | 46.723 / 45.010 | 1.052 / 1.286 | 55.521 / 54.684 |

Current public native totals across all thirteen calls; source attempts are per retained-core call, not hardware instructions

| Case | Publications | Native calls | Lowered operations | Code used bytes | Conditional calls | Whole-header calls | Compilation CPU | Source attempts/call |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 183 / 183 | 3,912,233 / 3,912,233 | 9,156,925 / 9,156,925 | 21,391 / 21,391 | 3,902,520 / 3,902,520 | 3,902,472 / 3,902,472 | 1.573 / 1.548 | 1,166,742 / 1,166,742 |
| minimal 100000 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0.016 / 0.016 | 2,000,035 / 2,000,035 |
| memset 100000 | 31 / 31 | 1,300,208 / 1,300,208 | 3,900,859 / 3,900,859 | 2,212 / 2,212 | 1,300,118 / 1,300,118 | 1,300,084 / 1,300,084 | 0.186 / 0.189 | 1,200,349 / 1,200,349 |
| pinky 1 | 335 / 335 | 28,051,881 / 28,051,881 | 156,172,295 / 156,172,295 | 37,060 / 37,060 | 17,569,870 / 17,569,870 | 13,669,609 / 13,669,609 | 1.378 / 1.350 | 32,055,270 / 32,055,270 |
| sieve 10000000 | 183 / 183 | 390,560,066 / 390,560,066 | 912,289,194 / 912,289,194 | 21,391 / 21,391 | 390,021,019 / 390,021,019 | 390,020,971 / 390,020,971 | 1.562 / 1.574 | 123,322,753 / 123,322,753 |
| init 0 | 1,024 / 1,024 | 13,958,022 / 13,958,022 | 62,653,474 / 62,653,474 | 94,745 / 94,745 | 7,246,148 / 7,246,148 | 6,377,298 / 6,377,298 | 6.591 / 6.597 | 203,298,231 / 203,298,231 |
| tick 0 | 462 / 462 | 5,674,903 / 5,674,903 | 21,853,912 / 21,853,912 | 41,648 / 41,648 | 1,815,881 / 1,815,881 | 1,809,870 / 1,809,870 | 1.926 / 1.901 | 15,523,334 / 15,523,334 |


ARM control, reused public calls only; each ratio uses its own ARM runner. The algorithm is
unchanged by this stack, and the previous/current equal-source JIT controls track closely.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.507 / 3.468 | 2.989 / 2.989 | 2.988 / 2.981 | 2.823 / 2.801 | 6.101 / 6.068 | 0.852 / 0.860 | 0.490 / 0.491 |
| minimal 100000 | 6.240 / 6.309 | 5.892 / 6.091 | 5.909 / 5.968 | 6.134 / 6.018 | 5.486 / 5.506 | 0.947 / 0.946 | 1.077 / 1.084 |
| memset 100000 | 4.463 / 4.450 | 4.455 / 4.469 | 4.471 / 4.405 | 3.637 / 3.628 | 3.739 / 3.754 | 1.002 / 0.990 | 1.196 / 1.173 |
| pinky 1 | 95.517 / 95.783 | 86.595 / 86.597 | 87.075 / 86.537 | 86.669 / 86.551 | 87.566 / 87.390 | 0.912 / 0.903 | 0.994 / 0.990 |
| sieve 10000000 | 343.791 / 337.116 | 287.058 / 287.419 | 287.243 / 286.306 | 288.001 / 289.354 | 333.661 / 333.663 | 0.836 / 0.849 | 0.861 / 0.858 |
| init 0 | 544.892 / 536.878 | 328.416 / 320.669 | 316.013 / 319.621 | 331.496 / 329.335 | 629.236 / 629.145 | 0.580 / 0.595 | 0.502 / 0.508 |
| tick 0 | 50.108 / 50.297 | 46.777 / 46.561 | 46.766 / 46.628 | 40.427 / 40.776 | 40.085 / 40.050 | 0.933 / 0.927 | 1.167 / 1.164 |

The full ARM receipt additionally retains owner/cold, core reset/publication and reference
lifecycle tables. ARM gameplay remains slower than the reference on both raw calls and full
invocation lifecycle (our public46.628–46.766ms; reference total42.504–42.996ms). This is an
existing ARM performance gap, not an x86 default-selection regression. No new optimization is
included after qualification. Next work can separately investigate cold compilation, tiny-loop
coverage, checked-memory/publication costs and the bounded initialization publication cap.

Production/runtime/build-selection/continuing-frame sources are identical to the qualified
`0031e64c` tree above; the measured46ca9b12 tree adds documentation and report formatting only.
Later documentation-only verdict publication preserves these measured-head identities.
