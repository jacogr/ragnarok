# exact-page-capacity

Keep exact validated page-image capacity: all six reused gameplay lifecycle pairs improve2.79–3.45% (median3.00%), while call-only timings stay essentially flat. Six cold-init pairs including the declared replication remain near flat; cold gameplay lifecycle-2.45%. Eight separate full-process RSS probes observe270.23–270.36MiB baseline vs232.08–232.20MiB candidate; these are whole-process peaks and their clocks are excluded. Complete208timed/4negative,8native/8ASan and fresh image/source/state checks pass.

Checked macOS arm64 CPU durations. Baseline commit `9244ec92814bb08f1a939b1a673cf0d1cc2503fb`; candidate overlay
`3b06ed393c8639fea426da60cc350448bfc6f38e104db522372448cbd378ffc9`. Memory overlay
`70ac616835b13596c29f409ed10b8dc2500fc51e0e77e02578a4525c049993e4`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | -0.08% | +0.00% | -0.52…+0.33% |
| sieve | -0.31% | +0.10% | -1.00…+0.65% |
| minimal | -0.37% | +0.02% | -0.67…+0.15% |
| memset | +0.09% | -0.19% | -0.16…+0.44% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 328.170 | 328.406 | +0.07% | -0.82% |
| init cold/1 | 325.802 | 326.238 | +0.13% | -0.31% |
| init cold/2 | 326.200 | 326.402 | +0.06% | -0.19% |
| init cold/3 | 325.873 | 327.802 | +0.59% | +0.21% |
| init cold/4 | 325.528 | 326.723 | +0.37% | +0.02% |
| init cold/5 | 325.741 | 326.084 | +0.11% | -0.07% |
| init reused/0 | 318.169 | 320.528 | +0.74% | +0.39% |
| init reused/1 | 320.043 | 318.987 | -0.33% | -0.78% |
| init reused/2 | 320.540 | 319.714 | -0.26% | -0.71% |
| init reused/3 | 320.486 | 319.277 | -0.38% | -0.93% |
| init reused/4 | 319.442 | 317.748 | -0.53% | -1.06% |
| init reused/5 | 317.849 | 317.755 | -0.03% | -0.57% |
| tick cold/0 | 32.210 | 31.882 | -1.02% | -3.14% |
| tick cold/1 | 31.220 | 31.396 | +0.56% | -1.75% |
| tick reused/0 | 28.689 | 28.645 | -0.15% | -2.79% |
| tick reused/1 | 28.671 | 28.509 | -0.57% | -3.45% |
| tick reused/2 | 28.759 | 28.723 | -0.13% | -3.29% |
| tick reused/3 | 28.694 | 28.595 | -0.35% | -2.94% |
| tick reused/4 | 28.701 | 28.642 | -0.21% | -2.89% |
| tick reused/5 | 28.672 | 28.788 | +0.40% | -3.06% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 86.212 / 86.637 | 86.213 / 86.479 | 118.359 / 118.867 | 92.599 / 92.894 | 0.931x / 0.931x |
| sieve | 3.212 / 3.208 | 3.211 / 3.208 | 3.352 / 3.345 | 5.757 / 5.786 | 0.558x / 0.555x |
| minimal | 5.115 / 5.113 | 5.104 / 5.101 | 7.250 / 7.250 | 5.922 / 5.904 | 0.862x / 0.864x |
| memset | 3.619 / 3.619 | 3.619 / 3.621 | 3.413 / 3.419 | 3.873 / 3.804 | 0.934x / 0.952x |
| init | 318.169 / 320.043 | 320.528 / 318.987 | 1323.120 / 1318.161 | 661.385 / 658.065 | 0.485x / 0.485x |
| tick | 28.689 / 28.671 | 28.645 / 28.509 | 84.372 / 84.454 | 34.079 / 34.274 | 0.841x / 0.832x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.363 | 18.227 | 11.980 | 236.405 | 53.153 | 19.939 | 0.007 |
| init/0/candidate | 7.362 | 13.585 | 10.818 | 238.056 | 53.437 | 20.354 | 0.008 |
| init/1/candidate | 7.652 | 13.634 | 10.483 | 237.057 | 53.072 | 20.026 | 0.007 |
| init/1/baseline | 7.782 | 19.963 | 12.001 | 237.761 | 53.654 | 20.099 | 0.007 |
| tick/0/baseline | 7.487 | 18.092 | 10.970 | 28.200 | 0.377 | 0.102 | 0.007 |
| tick/0/candidate | 7.373 | 13.714 | 9.878 | 28.145 | 0.381 | 0.101 | 0.007 |
| tick/1/candidate | 7.512 | 13.680 | 9.931 | 28.032 | 0.378 | 0.102 | 0.007 |
| tick/1/baseline | 7.435 | 18.079 | 11.032 | 28.181 | 0.378 | 0.102 | 0.007 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 372.736 | 363.677 | -2.43% |
| init/1 | 366.562 | 361.226 | -1.46% |
| init/2 | 366.573 | 361.013 | -1.52% |
| init/3 | 366.275 | 362.489 | -1.03% |
| init/4 | 365.947 | 360.997 | -1.35% |
| init/5 | 366.215 | 360.942 | -1.44% |
| tick/0 | 73.727 | 67.407 | -8.57% |
| tick/1 | 71.683 | 66.343 | -7.45% |

## Separate complete-process peak RSS

All clocks from these resource probes are discarded. RSS includes fixtures, validation
and every process owner; these are not engine-only allocation measurements.

| Phase/order/role | Peak MiB |
| --- | ---: |
| init/0/baseline | 270.23 |
| init/0/candidate | 232.20 |
| init/1/candidate | 232.20 |
| init/1/baseline | 270.23 |
| tick/0/baseline | 270.36 |
| tick/0/candidate | 232.08 |
| tick/1/candidate | 232.08 |
| tick/1/baseline | 270.36 |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 208 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
