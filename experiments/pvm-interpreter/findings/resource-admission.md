# resource-admission

Initial resource-admission model: all nine native/sanitizer groups and complete paired controls pass. Initialization reused +0.35%, gameplay -0.28%, memory fill +2.81% median. Preserve this cohort; final qualification follows moving cold policy metadata after the existing hot fields.

Checked macOS arm64 CPU durations. Baseline commit `59d017f2a378893b09c721229a2893331ee4a3cb`; candidate overlay
`f580ced192046e7894b9d95a182baa5a508e134576fb16c3d86fe9e984d7324e`. Memory overlay
`bc96ab1883864f99c943a5bc563bda8b37be29e5d49177127ec058d560e88f67`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | +0.70% | -0.09% | +0.17…+0.95% |
| sieve | -0.39% | +0.40% | -3.15…-0.28% |
| minimal | +0.27% | +0.25% | -1.30…+0.73% |
| memset | +2.81% | -1.98% | -3.44…+3.23% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 322.493 | 323.765 | +0.39% | +0.14% |
| init cold/1 | 325.225 | 327.268 | +0.63% | +0.68% |
| init reused/0 | 316.555 | 317.541 | +0.31% | +0.35% |
| init reused/1 | 315.298 | 316.471 | +0.37% | +0.29% |
| init reused/2 | 316.555 | 317.735 | +0.37% | +0.34% |
| init reused/3 | 316.310 | 317.322 | +0.32% | +0.30% |
| init reused/4 | 316.222 | 317.477 | +0.40% | +0.32% |
| init reused/5 | 313.197 | 314.048 | +0.27% | +0.38% |
| tick cold/0 | 30.101 | 30.662 | +1.86% | +1.60% |
| tick cold/1 | 30.850 | 30.056 | -2.57% | -1.84% |
| tick reused/0 | 27.799 | 27.663 | -0.49% | -0.57% |
| tick reused/1 | 27.662 | 27.643 | -0.07% | +0.15% |
| tick reused/2 | 27.810 | 27.582 | -0.82% | -0.93% |
| tick reused/3 | 27.588 | 27.628 | +0.14% | +0.07% |
| tick reused/4 | 27.678 | 27.829 | +0.54% | +0.20% |
| tick reused/5 | 27.841 | 27.669 | -0.62% | -1.13% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 82.719 / 82.207 | 82.805 / 82.850 | 117.920 / 118.305 | 93.216 / 92.193 | 0.888x / 0.899x |
| sieve | 3.211 / 3.203 | 3.185 / 3.192 | 3.363 / 3.373 | 5.872 / 5.830 | 0.542x / 0.547x |
| minimal | 4.792 / 4.800 | 4.803 / 4.800 | 7.248 / 7.229 | 5.915 / 5.913 | 0.812x / 0.812x |
| memset | 3.684 / 3.647 | 3.752 / 3.750 | 3.412 / 3.417 | 3.859 / 3.864 | 0.972x / 0.970x |
| init | 316.555 / 315.298 | 317.541 / 316.471 | 1322.124 / 1313.076 | 662.143 / 660.605 | 0.480x / 0.479x |
| tick | 27.799 / 27.662 | 27.663 / 27.643 | 83.835 / 83.764 | 34.075 / 34.166 | 0.812x / 0.809x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.397 | 14.426 | 10.326 | 234.478 | 53.562 | 20.116 | 0.007 |
| init/0/candidate | 7.733 | 14.229 | 10.397 | 235.269 | 53.791 | 20.110 | 0.007 |
| init/1/candidate | 7.707 | 14.117 | 10.345 | 234.848 | 53.447 | 20.092 | 0.007 |
| init/1/baseline | 7.425 | 14.236 | 10.402 | 233.643 | 53.328 | 19.990 | 0.007 |
| tick/0/baseline | 7.398 | 13.823 | 9.622 | 27.293 | 0.391 | 0.102 | 0.007 |
| tick/0/candidate | 7.503 | 13.991 | 9.716 | 27.180 | 0.387 | 0.103 | 0.007 |
| tick/1/candidate | 7.418 | 13.638 | 9.650 | 27.137 | 0.381 | 0.101 | 0.007 |
| tick/1/baseline | 7.344 | 13.642 | 9.644 | 27.178 | 0.378 | 0.102 | 0.007 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 360.327 | 360.298 | -0.01% |
| init/1 | 360.340 | 362.667 | +0.65% |
| tick/0 | 65.405 | 66.104 | +1.07% |
| tick/1 | 66.792 | 64.815 | -2.96% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 200 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
