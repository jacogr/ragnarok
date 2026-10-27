# store-register

Reject checked store/register composition: correctness and actual indirect-call removal pass, but memory-fill gain is small and mixed, while both cold gameplay calls regress. Retain boundary witnesses; runtime restored to parent.

Checked macOS arm64 CPU durations. Baseline commit `00c09d98fa44eadf6e2fb2d4c942ec5b5f40801e`; candidate overlay
`a9b1f2334ef7632d99bfd5d45b04e791fce4998f83d5f244b414eaa52fa48abc`. Memory overlay
`70ac616835b13596c29f409ed10b8dc2500fc51e0e77e02578a4525c049993e4`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | -0.13% | +0.39% | -1.74…+0.59% |
| sieve | -0.36% | +0.50% | -1.47…-0.08% |
| minimal | +0.21% | +0.48% | -1.11…+0.86% |
| memset | -1.05% | -1.52% | -3.37…+0.19% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 322.094 | 325.360 | +1.01% | +0.93% |
| init cold/1 | 323.376 | 321.130 | -0.69% | -0.70% |
| init reused/0 | 314.825 | 315.166 | +0.11% | +0.09% |
| init reused/1 | 315.370 | 314.784 | -0.19% | -0.21% |
| init reused/2 | 315.551 | 316.004 | +0.14% | +0.15% |
| init reused/3 | 314.340 | 317.002 | +0.85% | +0.72% |
| init reused/4 | 312.920 | 314.173 | +0.40% | +0.40% |
| init reused/5 | 312.449 | 313.382 | +0.30% | +0.24% |
| tick cold/0 | 29.629 | 30.370 | +2.50% | -1.36% |
| tick cold/1 | 29.830 | 30.457 | +2.10% | +2.29% |
| tick reused/0 | 27.292 | 27.501 | +0.77% | +1.51% |
| tick reused/1 | 27.485 | 27.604 | +0.43% | +0.04% |
| tick reused/2 | 27.596 | 27.488 | -0.39% | -0.30% |
| tick reused/3 | 27.325 | 28.170 | +3.09% | +2.69% |
| tick reused/4 | 27.807 | 27.640 | -0.60% | -0.47% |
| tick reused/5 | 27.804 | 27.403 | -1.44% | -1.85% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 82.612 / 82.909 | 82.447 / 83.005 | 117.228 / 116.927 | 90.691 / 90.748 | 0.909x / 0.915x |
| sieve | 3.120 / 3.111 | 3.115 / 3.109 | 3.312 / 3.270 | 5.732 / 5.713 | 0.543x / 0.544x |
| minimal | 4.777 / 4.758 | 4.774 / 4.699 | 7.160 / 7.199 | 5.808 / 5.807 | 0.822x / 0.809x |
| memset | 3.642 / 3.643 | 3.580 / 3.577 | 3.351 / 3.363 | 3.805 / 3.791 | 0.941x / 0.944x |
| init | 314.825 / 315.370 | 315.166 / 314.784 | 1311.184 / 1300.937 | 652.000 / 651.731 | 0.483x / 0.483x |
| tick | 27.292 / 27.485 | 27.501 / 27.604 | 83.472 / 84.126 | 33.681 / 33.627 | 0.817x / 0.821x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.486 | 13.639 | 10.331 | 233.048 | 53.093 | 20.067 | 0.007 |
| init/0/candidate | 7.320 | 13.858 | 10.220 | 233.976 | 53.104 | 19.985 | 0.007 |
| init/1/candidate | 7.504 | 14.294 | 10.200 | 233.811 | 52.925 | 19.889 | 0.007 |
| init/1/baseline | 7.475 | 13.806 | 10.438 | 233.977 | 53.294 | 20.072 | 0.007 |
| tick/0/baseline | 7.222 | 13.562 | 9.623 | 26.802 | 0.381 | 0.100 | 0.006 |
| tick/0/candidate | 7.268 | 13.487 | 9.739 | 26.946 | 0.380 | 0.099 | 0.006 |
| tick/1/candidate | 7.227 | 13.441 | 9.650 | 27.120 | 0.382 | 0.101 | 0.007 |
| tick/1/baseline | 7.290 | 13.395 | 9.681 | 27.002 | 0.378 | 0.100 | 0.006 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 356.708 | 360.353 | +1.02% |
| init/1 | 357.859 | 355.603 | -0.63% |
| tick/0 | 66.436 | 64.774 | -2.50% |
| tick/1 | 64.252 | 64.966 | +1.11% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 200 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
