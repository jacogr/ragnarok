# store-splice

Keep checked fast-store force-splicing. Paired kernel medians improve3.95% Pinky/1.06% sieve/5.89% Minimal; reused DOOM calls improve2.00% init/2.78% gameplay. Tradeoff: memory fill kernel+0.61%(all pairs+0.56..+0.92%) remains visible. Complete200timed/4negative,8native/8ASan, fresh equal images/source/full-state controls pass. Native code confirms fast-store calls removed in all3drivers, with checked slow fallback still referenced. Code size recorded separately; no hardware-cause claim.

Checked macOS arm64 CPU durations. Baseline commit `ea318738645412d9cc9f1171f0fe401d63db5997`; candidate overlay
`33b3b3baa63cdd981c5065e43d37877a4876fb2ef05f430b02398a744ca84935`. Memory overlay
`70ac616835b13596c29f409ed10b8dc2500fc51e0e77e02578a4525c049993e4`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | -3.95% | -3.83% | -4.50…-3.74% |
| sieve | -1.06% | -1.15% | -1.39…-0.40% |
| minimal | -5.89% | -6.92% | -6.85…-5.48% |
| memset | +0.61% | +0.51% | +0.56…+0.92% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 326.570 | 322.343 | -1.29% | -1.62% |
| init cold/1 | 328.900 | 324.479 | -1.34% | -1.06% |
| init reused/0 | 320.565 | 313.329 | -2.26% | -2.34% |
| init reused/1 | 318.262 | 315.264 | -0.94% | -0.83% |
| init reused/2 | 317.930 | 313.397 | -1.43% | -1.44% |
| init reused/3 | 321.166 | 313.427 | -2.41% | -2.29% |
| init reused/4 | 320.692 | 313.447 | -2.26% | -2.22% |
| init reused/5 | 318.882 | 313.303 | -1.75% | -1.69% |
| tick cold/0 | 31.682 | 30.771 | -2.88% | -1.58% |
| tick cold/1 | 31.508 | 30.616 | -2.83% | -1.94% |
| tick reused/0 | 28.562 | 27.860 | -2.46% | -1.96% |
| tick reused/1 | 28.879 | 28.025 | -2.96% | -1.83% |
| tick reused/2 | 28.558 | 27.692 | -3.03% | -2.70% |
| tick reused/3 | 28.477 | 27.762 | -2.51% | -2.00% |
| tick reused/4 | 28.752 | 27.672 | -3.75% | -3.60% |
| tick reused/5 | 28.605 | 27.860 | -2.61% | -2.59% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 86.194 / 85.933 | 82.365 / 82.150 | 118.107 / 118.096 | 92.489 / 92.453 | 0.891x / 0.889x |
| sieve | 3.211 / 3.212 | 3.174 / 3.173 | 3.333 / 3.359 | 5.811 / 5.812 | 0.546x / 0.546x |
| minimal | 5.086 / 5.098 | 4.781 / 4.794 | 7.227 / 7.252 | 5.910 / 5.898 | 0.809x / 0.813x |
| memset | 3.619 / 3.620 | 3.643 / 3.645 | 3.414 / 3.413 | 3.802 / 3.800 | 0.958x / 0.959x |
| init | 320.565 / 318.262 | 313.329 / 315.264 | 1313.624 / 1312.316 | 659.676 / 654.705 | 0.475x / 0.482x |
| tick | 28.562 / 28.879 | 27.860 / 28.025 | 84.005 / 84.670 | 33.737 / 33.882 | 0.826x / 0.827x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.351 | 13.598 | 10.374 | 238.676 | 53.480 | 20.148 | 0.007 |
| init/0/candidate | 7.243 | 13.539 | 10.287 | 231.952 | 52.874 | 19.923 | 0.007 |
| init/1/candidate | 7.419 | 13.629 | 10.482 | 233.304 | 53.392 | 20.061 | 0.007 |
| init/1/baseline | 7.358 | 13.598 | 10.207 | 236.534 | 53.208 | 20.012 | 0.007 |
| tick/0/baseline | 7.341 | 14.710 | 9.614 | 28.082 | 0.379 | 0.100 | 0.006 |
| tick/0/candidate | 7.422 | 13.784 | 9.624 | 27.365 | 0.387 | 0.101 | 0.007 |
| tick/1/candidate | 7.586 | 14.203 | 9.665 | 27.482 | 0.379 | 0.102 | 0.007 |
| tick/1/baseline | 7.419 | 13.760 | 9.650 | 28.184 | 0.387 | 0.101 | 0.006 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 364.004 | 357.643 | -1.75% |
| init/1 | 364.033 | 360.781 | -0.89% |
| tick/0 | 66.853 | 66.134 | -1.08% |
| tick/1 | 66.499 | 65.293 | -1.81% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 200 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
