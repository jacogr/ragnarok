# charged-cycle

Keep exact-handler-guarded nonrecursive charged cycles: all six reused initialization pairs improve2.45–3.19% (median3.06%); cold call-2.98%, reused lifecycle-2.98%. Small kernel medians within0.29%; reused gameplay call-0.03%, lifecycle-0.38%. Every logical block preserves gas/quota checks and original partial fallback; arbitrary exits return to ordinary dispatch. Full correctness/image/state/source controls and native-call gate pass.

Checked macOS arm64 CPU durations. Baseline commit `15763254ac129717e76cb3b1fe45490ad93cbe41`; candidate overlay
`f712410919449acc3f0bb3f0b118607710ed2796466a7f0e67d4e5f43b8ee5a2`. Memory overlay
`70ac616835b13596c29f409ed10b8dc2500fc51e0e77e02578a4525c049993e4`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | +0.05% | +0.03% | -1.14…+0.64% |
| sieve | -0.05% | -0.04% | -0.61…+0.79% |
| minimal | +0.29% | +0.17% | -0.30…+1.23% |
| memset | +0.13% | +0.03% | -0.67…+2.81% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 655.689 | 637.251 | -2.81% | -2.94% |
| init cold/1 | 650.139 | 629.618 | -3.16% | -3.12% |
| init reused/0 | 647.677 | 627.902 | -3.05% | -2.94% |
| init reused/1 | 647.504 | 627.591 | -3.08% | -3.03% |
| init reused/2 | 647.872 | 627.529 | -3.14% | -3.10% |
| init reused/3 | 643.372 | 627.602 | -2.45% | -2.47% |
| init reused/4 | 642.258 | 623.630 | -2.90% | -2.88% |
| init reused/5 | 642.181 | 621.718 | -3.19% | -3.17% |
| tick cold/0 | 31.623 | 31.155 | -1.48% | -3.34% |
| tick cold/1 | 31.344 | 31.102 | -0.77% | -1.04% |
| tick reused/0 | 28.829 | 28.846 | +0.06% | -0.61% |
| tick reused/1 | 28.704 | 28.802 | +0.34% | -0.12% |
| tick reused/2 | 28.930 | 28.927 | -0.01% | -0.73% |
| tick reused/3 | 28.909 | 28.858 | -0.18% | -0.16% |
| tick reused/4 | 28.948 | 28.893 | -0.19% | -0.95% |
| tick reused/5 | 28.946 | 28.933 | -0.05% | +0.49% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 85.834 / 86.525 | 85.834 / 86.543 | 118.079 / 119.415 | 91.606 / 91.364 | 0.937x / 0.947x |
| sieve | 3.232 / 3.232 | 3.244 / 3.235 | 3.374 / 3.332 | 5.719 / 5.737 | 0.567x / 0.564x |
| minimal | 5.120 / 5.101 | 5.111 / 5.120 | 7.205 / 7.198 | 5.810 / 5.814 | 0.880x / 0.881x |
| memset | 3.763 / 3.675 | 3.668 / 3.669 | 3.437 / 3.417 | 3.784 / 3.808 | 0.969x / 0.963x |
| init | 647.677 / 647.504 | 627.902 / 627.591 | 1321.378 / 1312.870 | 652.586 / 654.869 | 0.962x / 0.958x |
| tick | 28.829 / 28.704 | 28.846 / 28.802 | 84.726 / 84.838 | 33.727 / 34.351 | 0.855x / 0.838x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.303 | 18.138 | 11.743 | 565.543 | 53.852 | 20.049 | 0.007 |
| init/0/candidate | 7.368 | 18.516 | 12.038 | 545.286 | 53.852 | 20.123 | 0.007 |
| init/1/candidate | 7.383 | 18.681 | 12.098 | 545.738 | 53.565 | 20.200 | 0.007 |
| init/1/baseline | 7.459 | 18.670 | 12.168 | 564.934 | 53.764 | 19.963 | 0.007 |
| tick/0/baseline | 7.476 | 18.299 | 11.187 | 28.296 | 0.395 | 0.105 | 0.007 |
| tick/0/candidate | 7.318 | 18.268 | 11.023 | 28.344 | 0.391 | 0.105 | 0.007 |
| tick/1/candidate | 7.336 | 18.584 | 11.434 | 28.274 | 0.396 | 0.104 | 0.007 |
| tick/1/baseline | 7.405 | 18.691 | 11.402 | 28.215 | 0.388 | 0.104 | 0.008 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 702.248 | 677.874 | -3.47% |
| init/1 | 690.477 | 668.997 | -3.11% |
| tick/0 | 73.411 | 70.583 | -3.85% |
| tick/1 | 73.253 | 71.297 | -2.67% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 200 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
