# fixed-expanded

Keep stable concrete-record cycles with shared expanded branch selection: all six reused initialization pairs improve48.65–49.33% (median48.95%); cold calls improve48.59%, reused lifecycle47.99%. Small kernel medians+0.18% Pinky/-0.53% sieve/-0.12% Minimal/-1.22% fill; reused gameplay call-0.39%. Full200timed/4negative, fresh equal images, complete CPU/gas/source-attempt/memory/permission/host/source-state checks pass. All8native/8ASan groups plus51840additional conditional boundary cases pass; added tests do not change the measured runtime hash. Stable-coordinate and comparison expansion contributions still need a control before causal attribution.

Checked macOS arm64 CPU durations. Baseline commit `258df17403a94ae9307efcd622d7e3f6ced5d00d`; candidate overlay
`50874c74d866eaf49e1433467c446db23e8801f2f6abebc1d53c3ffecfaddae1`. Memory overlay
`70ac616835b13596c29f409ed10b8dc2500fc51e0e77e02578a4525c049993e4`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | +0.18% | -0.32% | -1.11…+0.53% |
| sieve | -0.53% | -0.76% | -0.63…-0.50% |
| minimal | -0.12% | -0.23% | -16.67…+0.08% |
| memset | -1.22% | -1.28% | -3.84…-0.74% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 633.157 | 325.647 | -48.57% | -47.65% |
| init cold/1 | 631.330 | 324.416 | -48.61% | -47.57% |
| init reused/0 | 623.766 | 320.327 | -48.65% | -47.71% |
| init reused/1 | 629.090 | 320.870 | -48.99% | -48.04% |
| init reused/2 | 626.718 | 317.534 | -49.33% | -48.53% |
| init reused/3 | 623.361 | 317.554 | -49.06% | -48.18% |
| init reused/4 | 624.207 | 318.899 | -48.91% | -47.93% |
| init reused/5 | 628.821 | 321.760 | -48.83% | -47.87% |
| tick cold/0 | 31.665 | 30.373 | -4.08% | +0.01% |
| tick cold/1 | 30.904 | 31.000 | +0.31% | +0.10% |
| tick reused/0 | 28.703 | 28.837 | +0.47% | +1.14% |
| tick reused/1 | 28.902 | 28.949 | +0.16% | -0.33% |
| tick reused/2 | 28.601 | 28.515 | -0.30% | -0.42% |
| tick reused/3 | 28.915 | 28.779 | -0.47% | -0.12% |
| tick reused/4 | 28.877 | 28.657 | -0.76% | -0.45% |
| tick reused/5 | 29.119 | 28.761 | -1.23% | -1.60% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 85.950 / 85.734 | 86.311 / 86.175 | 118.657 / 118.104 | 92.460 / 91.999 | 0.933x / 0.937x |
| sieve | 3.269 / 3.264 | 3.233 / 3.244 | 3.368 / 3.370 | 5.771 / 5.764 | 0.560x / 0.563x |
| minimal | 5.174 / 5.175 | 5.181 / 5.155 | 7.353 / 7.306 | 5.942 / 5.979 | 0.872x / 0.862x |
| memset | 3.684 / 3.679 | 3.635 / 3.634 | 3.422 / 3.463 | 3.797 / 4.007 | 0.957x / 0.907x |
| init | 623.766 / 629.090 | 320.327 / 320.870 | 1323.441 / 1313.361 | 659.472 / 658.192 | 0.486x / 0.488x |
| tick | 28.703 / 28.902 | 28.837 / 28.949 | 83.814 / 83.638 | 33.931 / 33.839 | 0.850x / 0.855x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.262 | 18.198 | 11.688 | 541.992 | 53.185 | 19.878 | 0.007 |
| init/0/candidate | 7.250 | 17.984 | 12.230 | 237.972 | 53.596 | 20.043 | 0.007 |
| init/1/candidate | 7.372 | 18.354 | 11.806 | 238.562 | 53.770 | 20.094 | 0.007 |
| init/1/baseline | 7.489 | 18.949 | 11.940 | 546.522 | 53.771 | 20.060 | 0.007 |
| tick/0/baseline | 7.306 | 17.924 | 10.956 | 28.222 | 0.376 | 0.102 | 0.006 |
| tick/0/candidate | 7.632 | 18.966 | 10.993 | 28.348 | 0.381 | 0.101 | 0.007 |
| tick/1/candidate | 7.286 | 18.155 | 11.148 | 28.267 | 0.373 | 0.100 | 0.007 |
| tick/1/baseline | 7.236 | 18.533 | 11.454 | 28.405 | 0.399 | 0.103 | 0.007 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 679.672 | 365.646 | -46.20% |
| init/1 | 670.809 | 364.270 | -45.70% |
| tick/0 | 72.630 | 72.106 | -0.72% |
| tick/1 | 71.084 | 71.121 | +0.05% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 200 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
