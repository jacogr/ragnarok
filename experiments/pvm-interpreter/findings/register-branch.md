# register-branch

Retain for the experimental branch: all six reused initialization pairs improve 2.13–3.94% (median 2.76%, roughly19ms). Small kernel medians -1.10% Pinky/-0.46% sieve/-0.98% Minimal/+0.05% fill. Qualified tradeoff: six cold gameplay lifecycle pairs regress0.98–2.56% (median1.71%, roughly0.8ms); cold gameplay call median+0.12%, reused call-0.38%. All original samples and fixed four-pair confirmation retained. Original cold validation, independently addressable branch and exact quota semantics preserved. This is not a uniform improvement or production promotion.

Checked macOS arm64 CPU durations. Baseline commit `57a6823fefef537f378906cfa369d100a7b7a529`; candidate overlay
`516c0fe3c33193b93dc49c6cc1f2121bfbe424de06b8b9a6e3f9e42310507370`. Memory overlay
`70ac616835b13596c29f409ed10b8dc2500fc51e0e77e02578a4525c049993e4`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | -1.10% | -0.40% | -2.47…-0.24% |
| sieve | -0.46% | -0.01% | -0.61…+0.09% |
| minimal | -0.98% | +0.00% | -1.29…-0.74% |
| memset | +0.05% | -0.02% | -0.50…+0.37% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 711.731 | 691.404 | -2.86% | -2.63% |
| init cold/1 | 708.161 | 688.024 | -2.84% | -2.76% |
| init reused/0 | 701.753 | 683.731 | -2.57% | -2.57% |
| init reused/1 | 701.107 | 680.347 | -2.96% | -2.83% |
| init reused/2 | 700.980 | 686.029 | -2.13% | -2.10% |
| init reused/3 | 708.402 | 684.097 | -3.43% | -3.39% |
| init reused/4 | 702.818 | 684.848 | -2.56% | -2.43% |
| init reused/5 | 708.184 | 680.308 | -3.94% | -3.89% |
| tick cold/0 | 31.546 | 31.383 | -0.52% | +2.56% |
| tick cold/1 | 31.433 | 31.979 | +1.74% | +1.55% |
| tick cold/2 | 31.476 | 31.285 | -0.61% | +2.40% |
| tick cold/3 | 30.950 | 31.022 | +0.23% | +0.98% |
| tick cold/4 | 30.597 | 30.599 | +0.01% | +1.73% |
| tick cold/5 | 30.878 | 31.568 | +2.23% | +1.69% |
| tick reused/0 | 28.950 | 28.878 | -0.25% | +0.23% |
| tick reused/1 | 28.796 | 28.979 | +0.64% | +0.75% |
| tick reused/2 | 28.826 | 28.680 | -0.51% | -1.04% |
| tick reused/3 | 28.952 | 28.769 | -0.63% | -0.17% |
| tick reused/4 | 28.792 | 28.841 | +0.17% | -0.34% |
| tick reused/5 | 28.855 | 28.669 | -0.64% | -1.68% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 87.680 / 87.096 | 86.579 / 86.462 | 119.380 / 118.480 | 92.832 / 92.981 | 0.933x / 0.930x |
| sieve | 3.404 / 3.308 | 3.388 / 3.369 | 3.379 / 3.510 | 5.986 / 6.178 | 0.566x / 0.545x |
| minimal | 5.357 / 5.255 | 5.152 / 5.157 | 7.354 / 7.479 | 5.928 / 5.968 | 0.869x / 0.864x |
| memset | 3.685 / 3.686 | 3.696 / 3.683 | 3.450 / 3.444 | 3.881 / 3.889 | 0.952x / 0.947x |
| init | 701.753 / 701.107 | 683.731 / 680.347 | 1325.925 / 1324.226 | 663.398 / 661.484 | 1.031x / 1.029x |
| tick | 28.950 / 28.796 | 28.878 / 28.979 | 84.670 / 83.916 | 34.315 / 34.066 | 0.842x / 0.851x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.263 | 18.448 | 11.803 | 620.387 | 53.241 | 19.866 | 0.007 |
| init/0/candidate | 7.380 | 19.776 | 11.674 | 601.633 | 53.532 | 20.018 | 0.007 |
| init/1/candidate | 7.367 | 20.970 | 12.059 | 598.239 | 53.483 | 19.953 | 0.007 |
| init/1/baseline | 7.426 | 18.416 | 11.675 | 619.616 | 53.090 | 19.878 | 0.007 |
| tick/0/baseline | 7.506 | 18.715 | 11.355 | 28.460 | 0.387 | 0.103 | 0.007 |
| tick/0/candidate | 7.504 | 18.629 | 11.528 | 28.354 | 0.402 | 0.106 | 0.007 |
| tick/1/candidate | 7.368 | 18.090 | 11.377 | 28.463 | 0.389 | 0.102 | 0.007 |
| tick/1/baseline | 7.388 | 18.317 | 11.315 | 28.299 | 0.387 | 0.102 | 0.007 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 751.662 | 732.471 | -2.55% |
| init/1 | 749.724 | 728.552 | -2.82% |
| tick/0 | 72.898 | 73.862 | +1.32% |
| tick/1 | 72.098 | 72.615 | +0.72% |
| tick/2 | 76.327 | 73.360 | -3.89% |
| tick/3 | 72.434 | 71.731 | -0.97% |
| tick/4 | 72.359 | 73.212 | +1.18% |
| tick/5 | 71.784 | 71.188 | -0.83% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 208 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
