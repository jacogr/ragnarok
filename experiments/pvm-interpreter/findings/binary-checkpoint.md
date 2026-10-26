# binary-checkpoint

Keep sparse checkpoint lookup: all six reused initialization call pairs improve 0.43–0.91% (median 0.61%); small-workload kernels are within 0.13% median of parent. Gameplay median +0.35% remains visible. Full semantics, lifecycle, source and image controls pass; this is a modest local host-boundary result.

Checked macOS arm64 CPU durations. Baseline commit `ee649d6032bb72fd628e97b63484692f1b20ebfe`; candidate overlay
`596e7cb857f9579d25754a0cca274489130b61969a29c69733a5593c1a9f3b6b`. Memory overlay
`70ac616835b13596c29f409ed10b8dc2500fc51e0e77e02578a4525c049993e4`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | +0.13% | -0.05% | -0.40…+0.52% |
| sieve | +0.05% | -0.04% | +0.00…+0.11% |
| minimal | -0.03% | -0.09% | -0.27…+0.19% |
| memset | +0.02% | -0.08% | -0.20…+0.11% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 715.404 | 712.237 | -0.44% | -0.75% |
| init cold/1 | 719.812 | 715.623 | -0.58% | -0.55% |
| init reused/0 | 713.692 | 708.176 | -0.77% | -0.79% |
| init reused/1 | 713.250 | 706.776 | -0.91% | -0.84% |
| init reused/2 | 712.773 | 708.826 | -0.55% | -0.53% |
| init reused/3 | 712.607 | 707.923 | -0.66% | -0.63% |
| init reused/4 | 708.804 | 705.755 | -0.43% | -0.49% |
| init reused/5 | 706.002 | 702.654 | -0.47% | -0.38% |
| tick cold/0 | 32.213 | 31.140 | -3.33% | -2.87% |
| tick cold/1 | 31.262 | 31.481 | +0.70% | +1.32% |
| tick reused/0 | 28.784 | 28.799 | +0.06% | -1.26% |
| tick reused/1 | 28.547 | 28.666 | +0.42% | -0.50% |
| tick reused/2 | 28.669 | 28.894 | +0.79% | +0.87% |
| tick reused/3 | 28.854 | 28.855 | +0.01% | +0.61% |
| tick reused/4 | 28.834 | 28.916 | +0.28% | -0.10% |
| tick reused/5 | 28.822 | 28.966 | +0.50% | +0.72% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 87.016 / 86.031 | 86.917 / 86.409 | 118.469 / 117.914 | 92.533 / 92.416 | 0.939x / 0.935x |
| sieve | 3.259 / 3.235 | 3.270 / 3.249 | 3.371 / 3.341 | 5.774 / 5.852 | 0.566x / 0.555x |
| minimal | 5.141 / 5.186 | 5.216 / 5.196 | 7.335 / 7.356 | 5.977 / 5.923 | 0.873x / 0.877x |
| memset | 3.708 / 3.707 | 3.717 / 3.712 | 3.458 / 3.441 | 3.881 / 3.811 | 0.958x / 0.974x |
| init | 713.692 / 713.250 | 708.176 / 706.776 | 1322.900 / 1313.660 | 655.657 / 655.414 | 1.080x / 1.078x |
| tick | 28.784 / 28.547 | 28.799 / 28.666 | 84.470 / 83.844 | 34.173 / 33.960 | 0.843x / 0.844x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.331 | 18.681 | 12.037 | 625.740 | 53.676 | 25.640 | 0.007 |
| init/0/candidate | 7.377 | 18.365 | 11.877 | 625.343 | 53.968 | 20.171 | 0.008 |
| init/1/candidate | 7.289 | 19.583 | 11.959 | 624.593 | 53.709 | 20.046 | 0.008 |
| init/1/baseline | 7.319 | 18.236 | 11.927 | 625.174 | 54.140 | 25.861 | 0.007 |
| tick/0/baseline | 7.361 | 17.919 | 11.681 | 28.142 | 0.413 | 0.100 | 0.007 |
| tick/0/candidate | 7.340 | 18.495 | 10.941 | 28.316 | 0.381 | 0.102 | 0.007 |
| tick/1/candidate | 7.364 | 18.257 | 10.892 | 28.177 | 0.382 | 0.101 | 0.007 |
| tick/1/baseline | 7.406 | 19.410 | 10.953 | 28.060 | 0.376 | 0.099 | 0.007 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 760.968 | 752.776 | -1.08% |
| init/1 | 760.452 | 756.403 | -0.53% |
| tick/0 | 71.876 | 70.590 | -1.79% |
| tick/1 | 71.131 | 72.352 | +1.72% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 200 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
