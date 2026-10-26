# active-stream-barrier

Keep correctness fix: bind partial source quotas to the active sealed stream, preserving exact attempt counts across overlapping cached suffixes and resets. Performance is a cost check, not grounds for restoring incorrect semantics.

Checked macOS arm64 CPU durations. Baseline commit `84b8cbe34424feff230ca88f20207c5654e39352`; candidate overlay
`59d76c7de7a0d8ff92f617040566c58afed3374bb1ba490eac55d4e5236b787c`. Memory overlay
`70ac616835b13596c29f409ed10b8dc2500fc51e0e77e02578a4525c049993e4`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | +0.42% | +0.31% | +0.25…+0.65% |
| sieve | -0.03% | +0.15% | -3.03…+0.52% |
| minimal | +0.28% | -0.18% | -0.15…+0.85% |
| memset | +0.08% | +0.13% | -0.06…+1.22% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 710.557 | 710.734 | +0.02% | +0.04% |
| init cold/1 | 717.736 | 715.301 | -0.34% | -0.40% |
| init reused/0 | 699.335 | 697.735 | -0.23% | -0.25% |
| init reused/1 | 710.144 | 703.651 | -0.91% | -0.99% |
| init reused/2 | 699.404 | 704.036 | +0.66% | +0.71% |
| init reused/3 | 701.811 | 705.631 | +0.54% | +0.49% |
| init reused/4 | 699.742 | 703.713 | +0.57% | +0.52% |
| init reused/5 | 705.468 | 702.576 | -0.41% | -0.39% |
| tick cold/0 | 30.544 | 31.608 | +3.48% | +1.35% |
| tick cold/1 | 30.814 | 30.854 | +0.13% | +0.88% |
| tick reused/0 | 28.828 | 28.372 | -1.58% | -1.29% |
| tick reused/1 | 29.499 | 30.194 | +2.35% | +1.88% |
| tick reused/2 | 28.854 | 28.763 | -0.32% | -0.31% |
| tick reused/3 | 28.839 | 28.608 | -0.80% | -0.87% |
| tick reused/4 | 28.448 | 28.596 | +0.52% | -0.29% |
| tick reused/5 | 29.136 | 29.087 | -0.17% | +0.87% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 84.674 / 85.316 | 84.916 / 85.776 | 115.835 / 116.359 | 91.002 / 90.695 | 0.933x / 0.946x |
| sieve | 3.175 / 3.169 | 3.175 / 3.174 | 3.269 / 3.271 | 5.713 / 5.709 | 0.556x / 0.556x |
| minimal | 5.028 / 5.023 | 5.037 / 5.043 | 7.114 / 7.114 | 5.814 / 5.804 | 0.866x / 0.869x |
| memset | 3.598 / 3.605 | 3.603 / 3.606 | 3.365 / 3.353 | 3.787 / 3.799 | 0.952x / 0.949x |
| init | 699.335 / 710.144 | 697.735 / 703.651 | 1299.726 / 1292.336 | 654.840 / 653.910 | 1.066x / 1.076x |
| tick | 28.828 / 29.499 | 28.372 / 30.194 | 84.586 / 87.918 | 34.080 / 34.579 | 0.833x / 0.873x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.294 | 18.730 | 11.867 | 612.542 | 52.976 | 25.220 | 0.006 |
| init/0/candidate | 7.346 | 18.199 | 11.716 | 611.312 | 53.020 | 25.022 | 0.006 |
| init/1/candidate | 7.359 | 18.022 | 11.895 | 615.579 | 53.698 | 25.271 | 0.007 |
| init/1/baseline | 7.408 | 18.481 | 12.023 | 621.319 | 53.766 | 25.564 | 0.006 |
| tick/0/baseline | 7.268 | 18.136 | 11.190 | 28.338 | 0.398 | 0.103 | 0.006 |
| tick/0/candidate | 7.400 | 18.058 | 11.152 | 27.899 | 0.377 | 0.099 | 0.006 |
| tick/1/candidate | 7.453 | 17.634 | 11.412 | 29.683 | 0.395 | 0.100 | 0.006 |
| tick/1/baseline | 7.447 | 18.422 | 11.271 | 28.990 | 0.389 | 0.101 | 0.007 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 751.280 | 751.837 | +0.07% |
| init/1 | 758.455 | 755.278 | -0.42% |
| tick/0 | 70.441 | 71.505 | +1.51% |
| tick/1 | 70.156 | 70.667 | +0.73% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 200 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
