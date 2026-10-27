# static-count

Reject source-count specialization: initialization improves 1.10%, but small workloads do not benefit and cold gameplay regresses in the two-pair cohort. Retain interior-entry accounting witnesses; runtime restored to accepted parent.

Checked macOS arm64 CPU durations. Baseline commit `aa1f020404fa4c71adae855e0e71adbe52cf9f5f`; candidate overlay
`f29b2225fe10558f4c50e920f375e462c73f00ad14c4558e12ea2676a6d29ffc`. Memory overlay
`70ac616835b13596c29f409ed10b8dc2500fc51e0e77e02578a4525c049993e4`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | -0.04% | +0.12% | -0.86…+0.56% |
| sieve | +0.23% | -0.02% | -0.16…+0.95% |
| minimal | -0.12% | -0.07% | -0.27…+0.10% |
| memset | +0.08% | -0.17% | -0.27…+0.16% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 323.938 | 322.143 | -0.55% | -0.59% |
| init cold/1 | 322.319 | 317.248 | -1.57% | -1.63% |
| init reused/0 | 313.243 | 310.210 | -0.97% | -0.89% |
| init reused/1 | 315.438 | 311.969 | -1.10% | -1.06% |
| init reused/2 | 315.897 | 312.392 | -1.11% | -1.06% |
| init reused/3 | 315.942 | 312.035 | -1.24% | -1.18% |
| init reused/4 | 315.607 | 312.009 | -1.14% | -1.15% |
| init reused/5 | 313.516 | 310.177 | -1.07% | -1.01% |
| tick cold/0 | 30.533 | 30.458 | -0.25% | +0.03% |
| tick cold/1 | 30.088 | 31.482 | +4.63% | +4.25% |
| tick reused/0 | 27.902 | 27.884 | -0.06% | +0.16% |
| tick reused/1 | 27.517 | 27.618 | +0.37% | +0.11% |
| tick reused/2 | 28.160 | 27.820 | -1.21% | -0.94% |
| tick reused/3 | 27.625 | 27.748 | +0.44% | +0.57% |
| tick reused/4 | 27.651 | 27.883 | +0.84% | +0.70% |
| tick reused/5 | 27.660 | 27.832 | +0.63% | +0.29% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 83.356 / 83.252 | 82.816 / 83.441 | 118.656 / 119.360 | 92.528 / 92.406 | 0.895x / 0.903x |
| sieve | 3.299 / 3.229 | 3.329 / 3.201 | 3.524 / 3.361 | 5.803 / 5.837 | 0.574x / 0.548x |
| minimal | 4.860 / 4.806 | 4.869 / 4.816 | 7.341 / 7.295 | 5.933 / 5.960 | 0.821x / 0.808x |
| memset | 3.650 / 3.678 | 3.654 / 3.689 | 3.431 / 3.453 | 3.821 / 3.803 | 0.956x / 0.970x |
| init | 313.243 / 315.438 | 310.210 / 311.969 | 1317.920 / 1319.127 | 662.909 / 657.779 | 0.468x / 0.474x |
| tick | 27.902 / 27.517 | 27.884 / 27.618 | 83.940 / 83.730 | 34.249 / 34.146 | 0.814x / 0.809x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.521 | 13.848 | 10.190 | 231.696 | 52.952 | 19.968 | 0.007 |
| init/0/candidate | 7.338 | 14.280 | 10.129 | 228.845 | 53.029 | 19.902 | 0.007 |
| init/1/candidate | 7.517 | 13.859 | 10.359 | 229.983 | 53.364 | 20.085 | 0.007 |
| init/1/baseline | 7.571 | 14.299 | 10.280 | 233.209 | 53.495 | 20.098 | 0.007 |
| tick/0/baseline | 7.370 | 13.967 | 9.649 | 27.416 | 0.382 | 0.100 | 0.006 |
| tick/0/candidate | 7.345 | 13.730 | 9.809 | 27.300 | 0.391 | 0.102 | 0.006 |
| tick/1/candidate | 7.403 | 13.916 | 9.727 | 27.095 | 0.384 | 0.102 | 0.007 |
| tick/1/baseline | 7.392 | 13.815 | 9.659 | 27.037 | 0.385 | 0.101 | 0.007 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 360.345 | 357.976 | -0.66% |
| init/1 | 358.347 | 352.366 | -1.67% |
| tick/0 | 65.974 | 65.207 | -1.16% |
| tick/1 | 65.162 | 67.349 | +3.36% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 200 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
