# resource-admission-final

Qualified node/page admission with original hot field layout: all nine native/sanitizer groups and paired controls pass. Kernel medians within 0.5%, memory fill +0.20%, reused DOOM initialization +0.13% and gameplay -0.06%. Superseded by final additional preparation-span allowance; no gain or hardware-cause claim.

Checked macOS arm64 CPU durations. Baseline commit `59d017f2a378893b09c721229a2893331ee4a3cb`; candidate overlay
`58675a32fb9bb7b476a7405a81fee1b5a85c2a36ce7ddf88812343884c11fb3d`. Memory overlay
`bc96ab1883864f99c943a5bc563bda8b37be29e5d49177127ec058d560e88f67`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | +0.41% | +0.05% | +0.12…+0.65% |
| sieve | +0.47% | +0.01% | -0.03…+0.96% |
| minimal | +0.22% | +0.72% | -0.72…+0.79% |
| memset | +0.20% | +0.09% | -0.05…+1.18% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 327.373 | 327.340 | -0.01% | +0.01% |
| init cold/1 | 322.542 | 323.932 | +0.43% | +0.28% |
| init reused/0 | 313.937 | 315.298 | +0.43% | +0.82% |
| init reused/1 | 316.905 | 314.596 | -0.73% | -0.65% |
| init reused/2 | 317.132 | 317.736 | +0.19% | +0.17% |
| init reused/3 | 317.494 | 317.565 | +0.02% | +0.00% |
| init reused/4 | 317.029 | 317.269 | +0.08% | +0.08% |
| init reused/5 | 314.160 | 314.916 | +0.24% | +0.36% |
| tick cold/0 | 30.041 | 30.193 | +0.51% | +1.29% |
| tick cold/1 | 30.408 | 30.590 | +0.60% | +1.34% |
| tick reused/0 | 27.707 | 27.693 | -0.05% | +0.40% |
| tick reused/1 | 27.561 | 27.541 | -0.07% | +0.17% |
| tick reused/2 | 27.749 | 27.775 | +0.09% | +0.13% |
| tick reused/3 | 27.844 | 27.848 | +0.01% | -0.58% |
| tick reused/4 | 27.895 | 27.651 | -0.88% | -1.29% |
| tick reused/5 | 27.860 | 27.673 | -0.67% | -0.80% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 82.424 / 83.518 | 82.983 / 83.861 | 118.456 / 119.034 | 92.454 / 93.035 | 0.898x / 0.901x |
| sieve | 3.171 / 3.171 | 3.190 / 3.179 | 3.336 / 3.333 | 5.827 / 5.812 | 0.547x / 0.547x |
| minimal | 4.790 / 4.806 | 4.785 / 4.779 | 7.248 / 7.209 | 5.916 / 5.913 | 0.809x / 0.808x |
| memset | 3.647 / 3.645 | 3.646 / 3.644 | 3.418 / 3.416 | 3.869 / 3.864 | 0.942x / 0.943x |
| init | 313.937 / 316.905 | 315.298 / 314.596 | 1324.780 / 1312.928 | 663.809 / 662.420 | 0.475x / 0.475x |
| tick | 27.707 / 27.561 | 27.693 / 27.541 | 84.096 / 83.805 | 34.178 / 34.298 | 0.810x / 0.803x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.538 | 14.652 | 10.345 | 232.008 | 53.541 | 19.924 | 0.007 |
| init/0/candidate | 7.493 | 13.526 | 10.745 | 233.107 | 53.796 | 20.037 | 0.007 |
| init/1/candidate | 7.489 | 13.522 | 10.403 | 232.727 | 53.556 | 19.967 | 0.007 |
| init/1/baseline | 7.447 | 13.889 | 10.422 | 234.185 | 54.084 | 20.110 | 0.007 |
| tick/0/baseline | 7.352 | 13.671 | 9.930 | 27.224 | 0.381 | 0.102 | 0.007 |
| tick/0/candidate | 7.515 | 14.118 | 9.925 | 27.198 | 0.392 | 0.102 | 0.007 |
| tick/1/candidate | 7.565 | 13.906 | 9.954 | 27.047 | 0.388 | 0.100 | 0.007 |
| tick/1/baseline | 7.407 | 13.584 | 9.887 | 27.075 | 0.383 | 0.102 | 0.007 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 362.977 | 362.987 | +0.00% |
| init/1 | 357.683 | 358.495 | +0.23% |
| tick/0 | 64.555 | 65.557 | +1.55% |
| tick/1 | 65.430 | 66.272 | +1.29% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 200 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
