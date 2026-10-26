# load-splice

Reject load-only force-splicing: Pinky paired median+0.002% and reused initialization-0.029% are effectively flat; memory fill+0.68% (including retained+5.43% pair), Minimal+0.22%, gameplay+0.33%. Complete200timed/4negative,8native/8ASan and fresh image/state/source controls pass. Restore only flatLoad to its original inline hint; keep measured store force-splicing.

Checked macOS arm64 CPU durations. Baseline commit `80350f567b066c5ac10916848d65811f8efc2e7c`; candidate overlay
`77737281f61efa8b4364e214cca2b5f4efd1a6b6dfa13e90db9e2b06af59243b`. Memory overlay
`70ac616835b13596c29f409ed10b8dc2500fc51e0e77e02578a4525c049993e4`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | +0.00% | +0.38% | -0.35…+0.19% |
| sieve | -0.54% | -0.36% | -1.06…+0.39% |
| minimal | +0.22% | +1.96% | -0.52…+1.06% |
| memset | +0.68% | +0.20% | +0.26…+5.43% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 324.023 | 320.034 | -1.23% | -1.12% |
| init cold/1 | 320.859 | 319.869 | -0.31% | -0.29% |
| init reused/0 | 313.228 | 313.524 | +0.09% | +0.06% |
| init reused/1 | 316.867 | 316.673 | -0.06% | -0.09% |
| init reused/2 | 316.337 | 316.509 | +0.05% | +0.07% |
| init reused/3 | 313.845 | 313.229 | -0.20% | -0.27% |
| init reused/4 | 313.558 | 313.570 | +0.00% | +0.01% |
| init reused/5 | 315.483 | 313.461 | -0.64% | -0.91% |
| tick cold/0 | 30.669 | 30.291 | -1.23% | +0.22% |
| tick cold/1 | 30.201 | 30.453 | +0.83% | +0.98% |
| tick reused/0 | 27.721 | 27.785 | +0.23% | -0.32% |
| tick reused/1 | 27.854 | 27.930 | +0.27% | -0.03% |
| tick reused/2 | 27.820 | 27.924 | +0.38% | -0.12% |
| tick reused/3 | 27.809 | 27.969 | +0.57% | +0.15% |
| tick reused/4 | 27.812 | 27.603 | -0.75% | -0.59% |
| tick reused/5 | 27.663 | 28.120 | +1.66% | +1.42% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 82.324 / 82.788 | 83.847 / 82.615 | 117.727 / 118.524 | 90.861 / 90.737 | 0.923x / 0.910x |
| sieve | 3.195 / 3.174 | 3.183 / 3.184 | 3.337 / 3.312 | 5.725 / 5.749 | 0.556x / 0.554x |
| minimal | 4.785 / 4.789 | 4.806 / 4.779 | 7.254 / 7.254 | 5.813 / 5.808 | 0.827x / 0.823x |
| memset | 3.643 / 3.648 | 3.825 / 3.654 | 3.360 / 3.413 | 3.806 / 3.795 | 1.005x / 0.963x |
| init | 313.228 / 316.867 | 313.524 / 316.673 | 1323.501 / 1321.008 | 656.196 / 654.157 | 0.478x / 0.484x |
| tick | 27.721 / 27.854 | 27.785 / 27.930 | 83.918 / 84.589 | 33.957 / 33.717 | 0.818x / 0.828x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.284 | 13.283 | 10.309 | 232.071 | 52.920 | 19.971 | 0.007 |
| init/0/candidate | 7.248 | 13.833 | 10.284 | 232.196 | 53.143 | 20.023 | 0.007 |
| init/1/candidate | 7.577 | 13.682 | 10.319 | 234.466 | 53.663 | 20.137 | 0.007 |
| init/1/baseline | 7.408 | 13.587 | 10.374 | 234.555 | 53.742 | 20.154 | 0.007 |
| tick/0/baseline | 7.348 | 13.847 | 9.934 | 27.215 | 0.389 | 0.100 | 0.007 |
| tick/0/candidate | 7.270 | 13.604 | 9.658 | 27.304 | 0.379 | 0.100 | 0.007 |
| tick/1/candidate | 7.333 | 13.801 | 9.807 | 27.423 | 0.395 | 0.104 | 0.007 |
| tick/1/baseline | 7.406 | 14.028 | 9.918 | 27.323 | 0.396 | 0.103 | 0.007 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 359.484 | 355.408 | -1.13% |
| init/1 | 355.467 | 354.235 | -0.35% |
| tick/0 | 64.744 | 64.812 | +0.11% |
| tick/1 | 64.620 | 65.303 | +1.06% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 200 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
