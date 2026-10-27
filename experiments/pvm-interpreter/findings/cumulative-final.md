# cumulative-final

Retain the accepted cumulative model: direct comparison against the starting checkpoint, all declared samples and full state checks. Local macOS arm64 only; frozen master and PolkaVM comparisons are call-only. No production integration claim.

Checked macOS arm64 CPU durations. Baseline commit `72c79e4d36ae9b51f5d3f971477f0bb4b144df7d`; candidate overlay
`33b3b3baa63cdd981c5065e43d37877a4876fb2ef05f430b02398a744ca84935`. Memory overlay
`70ac616835b13596c29f409ed10b8dc2500fc51e0e77e02578a4525c049993e4`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | -3.64% | -3.56% | -5.09…-2.99% |
| sieve | -1.84% | -1.88% | -2.63…-0.06% |
| minimal | -6.22% | -7.68% | -7.49…-5.81% |
| memset | -0.53% | -0.79% | -0.79…+0.44% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 727.253 | 329.538 | -54.69% | -54.13% |
| init cold/1 | 721.858 | 321.761 | -55.43% | -55.01% |
| init reused/0 | 715.740 | 316.216 | -55.82% | -55.65% |
| init reused/1 | 714.832 | 316.417 | -55.74% | -55.59% |
| init reused/2 | 719.479 | 316.658 | -55.99% | -55.82% |
| init reused/3 | 720.048 | 316.334 | -56.07% | -55.91% |
| init reused/4 | 718.393 | 313.302 | -56.39% | -56.26% |
| init reused/5 | 714.567 | 313.291 | -56.16% | -56.01% |
| tick cold/0 | 31.042 | 30.325 | -2.31% | -19.04% |
| tick cold/1 | 31.019 | 31.157 | +0.44% | -17.84% |
| tick reused/0 | 28.576 | 27.680 | -3.14% | -22.76% |
| tick reused/1 | 28.672 | 27.641 | -3.60% | -23.20% |
| tick reused/2 | 28.466 | 27.665 | -2.82% | -22.26% |
| tick reused/3 | 28.692 | 27.643 | -3.65% | -22.84% |
| tick reused/4 | 28.596 | 27.721 | -3.06% | -22.11% |
| tick reused/5 | 28.584 | 27.777 | -2.82% | -22.34% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 86.466 / 86.162 | 83.317 / 83.084 | 118.775 / 118.883 | 91.922 / 92.719 | 0.906x / 0.896x |
| sieve | 3.174 / 3.248 | 3.171 / 3.206 | 3.330 / 3.329 | 5.707 / 5.710 | 0.556x / 0.561x |
| minimal | 5.117 / 5.139 | 4.841 / 5.040 | 7.261 / 7.294 | 5.853 / 5.892 | 0.827x / 0.855x |
| memset | 3.683 / 3.724 | 3.685 / 3.682 | 3.389 / 3.452 | 3.825 / 3.807 | 0.963x / 0.967x |
| init | 715.740 / 714.832 | 316.216 / 316.417 | 1323.540 / 1310.331 | 655.713 / 652.946 | 0.482x / 0.485x |
| tick | 28.576 / 28.672 | 27.680 / 27.641 | 83.731 / 83.962 | 34.106 / 33.589 | 0.812x / 0.823x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.214 | 26.711 | 20.619 | 620.161 | 53.786 | 33.272 | 0.007 |
| init/0/candidate | 7.369 | 14.057 | 10.291 | 234.272 | 53.636 | 20.069 | 0.007 |
| init/1/candidate | 7.305 | 13.496 | 10.292 | 234.349 | 53.580 | 20.145 | 0.007 |
| init/1/baseline | 7.433 | 26.826 | 20.661 | 619.291 | 54.039 | 33.399 | 0.007 |
| tick/0/baseline | 7.294 | 27.843 | 19.776 | 28.099 | 0.374 | 0.098 | 0.006 |
| tick/0/candidate | 7.262 | 13.593 | 9.651 | 27.194 | 0.387 | 0.100 | 0.006 |
| tick/1/candidate | 7.300 | 13.573 | 9.646 | 27.157 | 0.386 | 0.101 | 0.007 |
| tick/1/baseline | 7.235 | 27.192 | 19.838 | 28.088 | 0.382 | 0.098 | 0.006 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 790.858 | 367.599 | -53.52% |
| init/1 | 779.107 | 356.897 | -54.19% |
| tick/0 | 87.799 | 64.479 | -26.56% |
| tick/1 | 88.198 | 65.202 | -26.07% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 200 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
