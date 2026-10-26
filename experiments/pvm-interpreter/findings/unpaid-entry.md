# unpaid-entry

Reject: separating unpaid headers from paid invocation entry does not improve the measured workload and regresses sieve/fill kernels. Restore the accepted runtime and retain the invariant and timing evidence.

Checked macOS arm64 CPU durations. Baseline commit `00750d0b0c7e956b311b442b032abcc7f2a22c08`; candidate overlay
`85b1a4b1f79d94f4019ec2a342dff71f688b3ee0db07d2e820ba6cb21b7175b2`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | -0.11% | -0.69% | -0.30…+0.29% |
| sieve | +1.48% | +0.84% | +0.67…+4.59% |
| minimal | -0.09% | -1.38% | -0.25…+0.30% |
| memset | +2.11% | +1.95% | +1.99…+4.76% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 717.164 | 720.517 | +0.47% | +0.43% |
| init cold/1 | 729.701 | 731.990 | +0.31% | +0.31% |
| init reused/0 | 717.958 | 721.923 | +0.55% | +0.52% |
| init reused/1 | 721.170 | 721.256 | +0.01% | -0.03% |
| init reused/2 | 718.923 | 722.204 | +0.46% | +0.39% |
| init reused/3 | 720.596 | 724.322 | +0.52% | +0.46% |
| init reused/4 | 718.166 | 720.654 | +0.35% | +0.40% |
| init reused/5 | 721.082 | 719.605 | -0.20% | -0.18% |
| tick cold/0 | 31.525 | 31.672 | +0.47% | -0.17% |
| tick cold/1 | 31.574 | 31.642 | +0.22% | -3.08% |
| tick reused/0 | 28.828 | 28.818 | -0.04% | +0.25% |
| tick reused/1 | 28.822 | 28.886 | +0.22% | +0.26% |
| tick reused/2 | 28.886 | 28.883 | -0.01% | -0.83% |
| tick reused/3 | 28.846 | 28.871 | +0.09% | +0.23% |
| tick reused/4 | 28.858 | 28.901 | +0.15% | +0.44% |
| tick reused/5 | 28.728 | 28.883 | +0.54% | +0.59% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 85.386 / 86.638 | 85.697 / 86.681 | 117.838 / 118.314 | 90.625 / 96.130 | 0.946x / 0.902x |
| sieve | 3.178 / 3.175 | 3.216 / 3.231 | 3.280 / 3.321 | 5.715 / 5.707 | 0.563x / 0.566x |
| minimal | 5.091 / 5.090 | 5.088 / 5.014 | 7.080 / 7.225 | 5.811 / 5.804 | 0.876x / 0.864x |
| memset | 3.671 / 3.676 | 3.747 / 3.738 | 3.353 / 3.458 | 3.792 / 3.793 | 0.988x / 0.985x |
| init | 717.958 / 721.170 | 721.923 / 721.256 | 1312.579 / 1313.341 | 659.585 / 665.117 | 1.095x / 1.084x |
| tick | 28.828 / 28.822 | 28.818 / 28.886 | 85.334 / 86.493 | 34.282 / 34.355 | 0.841x / 0.841x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.330 | 27.156 | 20.587 | 621.735 | 54.001 | 33.525 | 0.007 |
| init/0/candidate | 7.345 | 26.814 | 20.577 | 626.752 | 53.709 | 33.321 | 0.007 |
| init/1/candidate | 7.406 | 26.920 | 20.539 | 626.167 | 53.249 | 33.136 | 0.007 |
| init/1/baseline | 7.411 | 27.338 | 20.723 | 624.874 | 53.904 | 33.480 | 0.007 |
| tick/0/baseline | 7.430 | 27.663 | 19.711 | 28.322 | 0.400 | 0.101 | 0.007 |
| tick/0/candidate | 7.457 | 27.277 | 19.873 | 28.325 | 0.391 | 0.100 | 0.007 |
| tick/1/candidate | 7.519 | 27.319 | 20.267 | 28.355 | 0.401 | 0.097 | 0.007 |
| tick/1/baseline | 7.305 | 27.692 | 20.070 | 28.323 | 0.391 | 0.091 | 0.006 |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 200 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.

## Interpretation and restoration

Reject and restore the exact accepted runtime. Removing the paid-flag load/branch from ordinary
headers saves two static ARM64 instructions (121 to119), but does not establish a CPU gain.
The complete native/ASan witnesses passed. A separate assertion-instrumented DOOM image proved
70,220,477 ordinary headers entered unpaid and1,621invocation/reentry headers entered paid;
both native and ASan runs agreed and all their clocks were discarded. The instrumenter source
is archived in `unpaid-entry-proof.py.txt`; reconstruct the trial with `unpaid-entry.patch` before
using it. Raw probe sources, full outputs and assertions remain under the ignored unpaid-proof
folder. No default/API change, CI, PR or merge. Prior accepted Nim source/check bytes are restored.
