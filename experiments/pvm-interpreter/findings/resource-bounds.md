# resource-bounds

Keep typed resource admission and finite node/preparation budgets. All 208 timed processes and four negative controls pass with every declared pair retained. Reused medians Pinky +0.98%, DOOM gameplay +1.15%, initialization +0.40%, Minimal +0.41%; sieve/fill flat. Cold gameplay six-pair median +1.11% with retained outliers. This is measured overhead for bounded preparation, not a speed improvement. Ten native and ten sanitizer groups qualify the unchanged measured runtime; fresh equal-image and full reference/source checks pass.

Checked macOS arm64 CPU durations. Baseline commit `59d017f2a378893b09c721229a2893331ee4a3cb`; candidate overlay
`e82444e621d1cd66cf607bea1b479e249714aaa73e8c2009e1e25077ebed5fb1`. Memory overlay
`bc96ab1883864f99c943a5bc563bda8b37be29e5d49177127ec058d560e88f67`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | +0.98% | +1.12% | +0.81…+1.35% |
| sieve | -0.09% | +0.29% | -0.24…+0.44% |
| minimal | +0.41% | +1.03% | -0.32…+0.72% |
| memset | -0.04% | +0.14% | -0.25…+0.07% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 324.911 | 324.194 | -0.22% | -0.55% |
| init cold/1 | 324.698 | 327.954 | +1.00% | +1.15% |
| init reused/0 | 316.040 | 317.861 | +0.58% | +0.51% |
| init reused/1 | 313.005 | 314.500 | +0.48% | +0.41% |
| init reused/2 | 315.579 | 317.187 | +0.51% | +0.59% |
| init reused/3 | 316.507 | 317.500 | +0.31% | +0.33% |
| init reused/4 | 315.339 | 314.491 | -0.27% | -0.41% |
| init reused/5 | 313.901 | 314.643 | +0.24% | +0.12% |
| tick cold/0 | 30.252 | 31.787 | +5.07% | +3.90% |
| tick cold/1 | 30.403 | 30.476 | +0.24% | -0.57% |
| tick cold/2 | 30.057 | 30.070 | +0.04% | +1.27% |
| tick cold/3 | 30.098 | 30.693 | +1.98% | +1.47% |
| tick cold/4 | 29.477 | 31.744 | +7.69% | +4.57% |
| tick cold/5 | 31.436 | 31.302 | -0.43% | -1.62% |
| tick reused/0 | 27.646 | 28.113 | +1.69% | +1.94% |
| tick reused/1 | 27.645 | 27.891 | +0.89% | +0.87% |
| tick reused/2 | 27.639 | 28.015 | +1.36% | +1.74% |
| tick reused/3 | 27.539 | 27.770 | +0.84% | +0.52% |
| tick reused/4 | 27.596 | 27.957 | +1.31% | +1.10% |
| tick reused/5 | 27.823 | 28.098 | +0.99% | +0.37% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 82.490 / 83.860 | 83.555 / 84.319 | 118.201 / 119.195 | 93.080 / 92.939 | 0.898x / 0.907x |
| sieve | 3.172 / 3.171 | 3.168 / 3.170 | 3.359 / 3.333 | 5.825 / 5.846 | 0.544x / 0.542x |
| minimal | 4.779 / 4.783 | 4.798 / 4.801 | 7.224 / 7.246 | 5.919 / 5.910 | 0.811x / 0.812x |
| memset | 3.650 / 3.650 | 3.644 / 3.642 | 3.413 / 3.414 | 3.864 / 3.861 | 0.943x / 0.943x |
| init | 316.040 / 313.005 | 317.861 / 314.500 | 1323.709 / 1312.609 | 661.771 / 657.857 | 0.480x / 0.478x |
| tick | 27.646 / 27.645 | 28.113 / 27.891 | 83.590 / 83.868 | 33.492 / 34.044 | 0.839x / 0.819x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.511 | 13.961 | 10.395 | 233.919 | 53.513 | 20.120 | 0.007 |
| init/0/candidate | 7.525 | 14.122 | 10.379 | 235.708 | 53.407 | 20.131 | 0.007 |
| init/1/candidate | 7.444 | 13.582 | 10.313 | 233.226 | 52.885 | 19.901 | 0.007 |
| init/1/baseline | 7.325 | 13.400 | 10.154 | 231.863 | 52.853 | 19.902 | 0.007 |
| tick/0/baseline | 7.238 | 13.306 | 9.630 | 27.155 | 0.382 | 0.101 | 0.007 |
| tick/0/candidate | 7.339 | 13.448 | 9.625 | 27.629 | 0.378 | 0.102 | 0.007 |
| tick/1/candidate | 7.315 | 13.496 | 9.649 | 27.409 | 0.383 | 0.101 | 0.007 |
| tick/1/baseline | 7.319 | 13.602 | 9.630 | 27.160 | 0.380 | 0.101 | 0.007 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 362.946 | 361.127 | -0.50% |
| init/1 | 360.698 | 364.465 | +1.04% |
| tick/0 | 64.537 | 66.797 | +3.50% |
| tick/1 | 65.045 | 64.437 | -0.93% |
| tick/2 | 63.722 | 64.740 | +1.60% |
| tick/3 | 64.405 | 65.225 | +1.27% |
| tick/4 | 63.979 | 66.297 | +3.62% |
| tick/5 | 66.990 | 66.408 | -0.87% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 208 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
