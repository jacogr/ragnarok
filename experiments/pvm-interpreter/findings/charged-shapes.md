# charged-shapes

Reject composed charged workers: reused initialization median-0.99%, but gameplay+3.53%, Pinky+2.07% and Minimal+2.48%. Actual ARM64 hot shapes call flatReserve out of line; two also call flatFusedRegisters. These static call facts do not alone establish CPU cause. Preserve complete correctness and timing evidence; restore runtime to accepted parent.

Checked macOS arm64 CPU durations. Baseline commit `34bf60beadf3a416e47755ce2cb33447838b1a92`; candidate overlay
`bd77c0902000cc14db328bc98591bcb2586847ea08ac90d590ba73f9d2f7619c`. Memory overlay
`70ac616835b13596c29f409ed10b8dc2500fc51e0e77e02578a4525c049993e4`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | +2.07% | +1.98% | +1.57…+2.40% |
| sieve | +0.20% | +0.70% | -0.78…+1.77% |
| minimal | +2.48% | +2.09% | +1.64…+2.92% |
| memset | -1.31% | -0.55% | -1.52…-1.01% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 691.734 | 686.050 | -0.82% | -0.91% |
| init cold/1 | 680.968 | 680.445 | -0.08% | -0.06% |
| init reused/0 | 682.677 | 676.980 | -0.83% | -0.81% |
| init reused/1 | 683.759 | 677.003 | -0.99% | -1.01% |
| init reused/2 | 688.071 | 672.871 | -2.21% | -2.18% |
| init reused/3 | 680.538 | 673.095 | -1.09% | -1.14% |
| init reused/4 | 680.041 | 676.505 | -0.52% | -0.47% |
| init reused/5 | 684.627 | 677.787 | -1.00% | -1.01% |
| tick cold/0 | 31.434 | 32.373 | +2.99% | +0.63% |
| tick cold/1 | 31.113 | 32.820 | +5.49% | -1.94% |
| tick reused/0 | 28.773 | 29.843 | +3.72% | +2.94% |
| tick reused/1 | 28.637 | 29.570 | +3.26% | +2.70% |
| tick reused/2 | 28.699 | 29.617 | +3.20% | +1.57% |
| tick reused/3 | 28.535 | 29.603 | +3.74% | +3.45% |
| tick reused/4 | 28.799 | 29.762 | +3.34% | +2.88% |
| tick reused/5 | 28.529 | 29.729 | +4.21% | +2.61% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 85.675 / 86.196 | 87.662 / 88.215 | 117.509 / 118.713 | 92.200 / 92.716 | 0.951x / 0.951x |
| sieve | 3.237 / 3.229 | 3.276 / 3.273 | 3.348 / 3.346 | 5.814 / 5.713 | 0.563x / 0.573x |
| minimal | 5.090 / 5.096 | 5.242 / 5.219 | 7.194 / 7.236 | 5.885 / 5.961 | 0.891x / 0.876x |
| memset | 3.673 / 3.660 | 3.616 / 3.635 | 3.410 / 3.413 | 3.790 / 3.796 | 0.954x / 0.957x |
| init | 682.677 / 683.759 | 676.980 / 677.003 | 1319.605 / 1322.753 | 655.869 / 658.707 | 1.032x / 1.028x |
| tick | 28.773 / 28.637 | 29.843 / 29.570 | 84.484 / 83.912 | 33.974 / 34.088 | 0.878x / 0.867x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.392 | 18.079 | 11.942 | 600.042 | 53.644 | 20.067 | 0.007 |
| init/0/candidate | 7.314 | 18.687 | 11.881 | 594.568 | 53.805 | 20.049 | 0.007 |
| init/1/candidate | 7.427 | 18.645 | 11.922 | 595.039 | 53.892 | 20.114 | 0.007 |
| init/1/baseline | 7.565 | 18.411 | 11.799 | 600.790 | 53.702 | 20.108 | 0.007 |
| tick/0/baseline | 7.378 | 18.262 | 10.915 | 28.297 | 0.376 | 0.100 | 0.007 |
| tick/0/candidate | 7.323 | 18.570 | 11.053 | 29.364 | 0.378 | 0.101 | 0.007 |
| tick/1/candidate | 7.327 | 18.363 | 11.081 | 29.067 | 0.374 | 0.101 | 0.007 |
| tick/1/baseline | 7.366 | 18.661 | 11.026 | 28.150 | 0.381 | 0.101 | 0.007 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 733.013 | 726.854 | -0.84% |
| init/1 | 720.267 | 719.613 | -0.09% |
| tick/0 | 73.552 | 72.951 | -0.82% |
| tick/1 | 74.259 | 72.563 | -2.28% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 200 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
