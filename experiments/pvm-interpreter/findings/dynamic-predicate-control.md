# dynamic-predicate-control

Reject attribution control and retain concrete coordinates. With shared branch expansion unchanged, dynamic-coordinate cycles regress reused initialization91.61–93.95% (median92.89%) versus fixed records. Complete200timed/4negative,8native/8ASan groups including51840condition vectors, fresh equal images, exact source and full reference state all pass. This isolates coordinate stability as necessary for the measured large gain; it does not identify a hardware cause. Restore only this control runtime to cb5fd0dc.

Checked macOS arm64 CPU durations. Baseline commit `cb5fd0dcd0c22a0c5c235ee998b7a09a652d69ea`; candidate overlay
`8c5a2b42074dfd74cfd7a40b1044b5382c96f6a2e71054b61eb17d9aab908395`. Memory overlay
`70ac616835b13596c29f409ed10b8dc2500fc51e0e77e02578a4525c049993e4`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | -0.11% | +0.38% | -0.21…+0.11% |
| sieve | -0.18% | +0.27% | -0.69…+0.71% |
| minimal | +0.31% | +0.03% | -0.14…+1.47% |
| memset | +0.08% | -0.17% | -0.52…+1.49% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 323.803 | 621.934 | +92.07% | +87.98% |
| init cold/1 | 327.524 | 623.165 | +90.27% | +86.43% |
| init reused/0 | 320.497 | 614.909 | +91.86% | +88.60% |
| init reused/1 | 319.194 | 613.537 | +92.21% | +88.91% |
| init reused/2 | 317.847 | 616.040 | +93.82% | +90.54% |
| init reused/3 | 320.492 | 614.090 | +91.61% | +88.25% |
| init reused/4 | 320.910 | 621.186 | +93.57% | +89.94% |
| init reused/5 | 317.622 | 616.021 | +93.95% | +90.78% |
| tick cold/0 | 31.111 | 32.514 | +4.51% | +2.29% |
| tick cold/1 | 31.174 | 31.342 | +0.54% | -0.41% |
| tick reused/0 | 28.936 | 28.898 | -0.13% | -1.75% |
| tick reused/1 | 28.815 | 29.139 | +1.12% | +1.51% |
| tick reused/2 | 28.761 | 28.884 | +0.43% | -0.81% |
| tick reused/3 | 28.895 | 28.834 | -0.21% | +0.08% |
| tick reused/4 | 28.805 | 29.026 | +0.77% | -0.04% |
| tick reused/5 | 28.858 | 29.035 | +0.61% | -0.60% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 86.072 / 87.130 | 85.756 / 85.932 | 118.466 / 118.282 | 90.846 / 92.024 | 0.944x / 0.934x |
| sieve | 3.208 / 3.211 | 3.204 / 3.211 | 3.373 / 3.341 | 5.708 / 5.811 | 0.561x / 0.553x |
| minimal | 5.117 / 5.107 | 5.114 / 5.110 | 7.228 / 7.240 | 5.820 / 5.921 | 0.879x / 0.863x |
| memset | 3.619 / 3.619 | 3.624 / 3.591 | 3.417 / 3.413 | 3.792 / 3.791 | 0.956x / 0.948x |
| init | 320.497 / 319.194 | 614.909 / 613.537 | 1322.162 / 1311.490 | 656.687 / 654.414 | 0.936x / 0.938x |
| tick | 28.936 / 28.815 | 28.898 / 29.139 | 84.370 / 90.941 | 33.593 / 34.090 | 0.860x / 0.855x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.381 | 18.320 | 11.799 | 237.892 | 54.077 | 20.082 | 0.007 |
| init/0/candidate | 7.347 | 18.951 | 12.135 | 532.285 | 53.970 | 20.061 | 0.007 |
| init/1/candidate | 7.414 | 17.977 | 11.598 | 531.593 | 53.737 | 19.999 | 0.007 |
| init/1/baseline | 7.874 | 19.379 | 11.633 | 237.125 | 53.682 | 19.931 | 0.007 |
| tick/0/baseline | 7.450 | 20.482 | 11.530 | 28.438 | 0.407 | 0.108 | 0.007 |
| tick/0/candidate | 7.470 | 19.219 | 10.873 | 28.410 | 0.384 | 0.102 | 0.007 |
| tick/1/candidate | 7.720 | 19.565 | 11.472 | 28.616 | 0.419 | 0.106 | 0.007 |
| tick/1/baseline | 7.439 | 19.516 | 11.169 | 28.323 | 0.387 | 0.105 | 0.007 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 364.973 | 662.790 | +81.60% |
| init/1 | 368.000 | 663.060 | +80.18% |
| tick/0 | 72.702 | 72.355 | -0.48% |
| tick/1 | 71.278 | 71.181 | -0.14% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 200 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
