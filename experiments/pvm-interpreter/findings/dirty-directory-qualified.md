# dirty-directory-qualified

Reject the dirty publication directory: reused initialization median improves only 0.70%, while Minimal kernels regress 5.52% and Pinky 1.63%. Preserve all complete-state and lifecycle evidence; restore only this isolated runtime change.

Checked macOS arm64 CPU durations. Baseline commit `9e3317d5e7b7d0c186443e865d6909204d0b1f9a`; candidate overlay
`0fa230a01bb22253c032522fa1281dfe9c7ecda42e65d749ed2f284f83723b14`. Memory overlay
`70ac616835b13596c29f409ed10b8dc2500fc51e0e77e02578a4525c049993e4`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | +1.63% | +1.67% | +0.26…+2.32% |
| sieve | +0.71% | +0.49% | -0.77…+1.76% |
| minimal | +5.52% | +3.98% | +2.91…+6.90% |
| memset | -0.16% | -0.06% | -1.29…+1.41% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 707.247 | 704.315 | -0.41% | -0.44% |
| init cold/1 | 707.788 | 697.713 | -1.42% | -1.47% |
| init reused/0 | 702.077 | 698.957 | -0.44% | -0.42% |
| init reused/1 | 703.775 | 704.402 | +0.09% | +0.10% |
| init reused/2 | 703.791 | 700.856 | -0.42% | -0.48% |
| init reused/3 | 708.201 | 699.102 | -1.28% | -1.34% |
| init reused/4 | 702.056 | 693.992 | -1.15% | -1.28% |
| init reused/5 | 708.813 | 702.090 | -0.95% | -1.00% |
| tick cold/0 | 31.603 | 31.371 | -0.73% | -0.44% |
| tick cold/1 | 32.066 | 32.251 | +0.58% | -1.41% |
| tick reused/0 | 28.656 | 29.793 | +3.97% | +2.07% |
| tick reused/1 | 28.675 | 28.941 | +0.93% | +0.54% |
| tick reused/2 | 28.685 | 29.050 | +1.27% | +0.19% |
| tick reused/3 | 28.666 | 29.922 | +4.38% | +4.23% |
| tick reused/4 | 28.979 | 29.217 | +0.82% | -0.68% |
| tick reused/5 | 28.916 | 29.861 | +3.27% | +2.43% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 85.571 / 86.983 | 87.333 / 86.898 | 117.077 / 118.579 | 91.397 / 91.405 | 0.956x / 0.951x |
| sieve | 3.216 / 3.213 | 3.231 / 3.229 | 3.329 / 3.336 | 5.761 / 5.771 | 0.561x / 0.560x |
| minimal | 5.126 / 5.121 | 5.345 / 5.324 | 7.193 / 7.179 | 5.851 / 5.868 | 0.913x / 0.907x |
| memset | 3.670 / 3.632 | 3.628 / 3.696 | 3.400 / 3.392 | 3.814 / 3.812 | 0.951x / 0.970x |
| init | 702.077 / 703.775 | 698.957 / 704.402 | 1317.763 / 1322.785 | 653.798 / 652.362 | 1.069x / 1.080x |
| tick | 28.656 / 28.675 | 29.793 / 28.941 | 83.938 / 83.986 | 33.734 / 33.630 | 0.883x / 0.861x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.225 | 18.344 | 11.938 | 614.295 | 53.679 | 25.398 | 0.007 |
| init/0/candidate | 7.205 | 17.990 | 11.815 | 620.347 | 44.282 | 25.689 | 0.000 |
| init/1/candidate | 7.383 | 18.801 | 11.884 | 624.971 | 44.834 | 25.900 | 0.000 |
| init/1/baseline | 7.372 | 21.439 | 11.851 | 614.265 | 53.922 | 25.500 | 0.006 |
| tick/0/baseline | 7.597 | 22.012 | 11.298 | 28.160 | 0.381 | 0.098 | 0.006 |
| tick/0/candidate | 7.209 | 17.791 | 10.964 | 29.210 | 0.456 | 0.107 | 0.000 |
| tick/1/candidate | 7.210 | 18.464 | 11.030 | 28.362 | 0.472 | 0.109 | 0.000 |
| tick/1/baseline | 7.261 | 18.427 | 11.174 | 28.189 | 0.387 | 0.098 | 0.007 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 749.008 | 745.400 | -0.48% |
| init/1 | 748.325 | 737.198 | -1.49% |
| tick/0 | 71.071 | 71.915 | +1.19% |
| tick/1 | 74.583 | 73.424 | -1.55% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 200 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
