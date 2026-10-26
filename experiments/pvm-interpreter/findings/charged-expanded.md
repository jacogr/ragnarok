# charged-expanded

Keep template-expanded charged register blocks: reused initialization improves in all six pairs3.96–5.35% (median4.96%); cold call median-5.29%, reused lifecycle-4.93%. Small kernels within0.35% median. Gameplay call median+0.51% and cold+0.95% remain visible; reset-inclusive reused/cold lifecycles are-0.07%/+0.11%, essentially flat. Actual ARM64 confirms composed helper calls absent; static code facts do not alone establish CPU cause. Full correctness/image/state/source controls pass.

Checked macOS arm64 CPU durations. Baseline commit `6e312d89861795072ac27bd8c16884c6fc64e8fe`; candidate overlay
`f69fef941f069d90d6514079290b0b74883f4a9ba2c5b826136d3f4a5f8c7776`. Memory overlay
`70ac616835b13596c29f409ed10b8dc2500fc51e0e77e02578a4525c049993e4`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | +0.35% | +0.14% | -0.56…+0.44% |
| sieve | +0.00% | -0.05% | -0.05…+0.03% |
| minimal | +0.29% | -0.30% | +0.08…+1.63% |
| memset | -0.07% | -0.05% | -0.31…+0.19% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 687.229 | 651.286 | -5.23% | -5.41% |
| init cold/1 | 688.494 | 651.593 | -5.36% | -5.25% |
| init reused/0 | 684.936 | 654.644 | -4.42% | -4.29% |
| init reused/1 | 685.779 | 649.085 | -5.35% | -5.14% |
| init reused/2 | 685.138 | 649.631 | -5.18% | -5.06% |
| init reused/3 | 679.865 | 644.924 | -5.14% | -5.06% |
| init reused/4 | 678.508 | 646.102 | -4.78% | -4.81% |
| init reused/5 | 680.013 | 653.053 | -3.96% | -3.72% |
| tick cold/0 | 30.830 | 31.188 | +1.16% | -0.05% |
| tick cold/1 | 31.762 | 31.996 | +0.74% | +0.28% |
| tick reused/0 | 28.936 | 29.012 | +0.26% | -0.25% |
| tick reused/1 | 28.690 | 28.883 | +0.67% | +1.69% |
| tick reused/2 | 28.791 | 28.889 | +0.34% | +0.11% |
| tick reused/3 | 28.596 | 28.906 | +1.08% | +1.65% |
| tick reused/4 | 28.913 | 28.916 | +0.01% | -1.04% |
| tick reused/5 | 28.825 | 29.030 | +0.71% | -0.31% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 86.067 / 85.833 | 86.168 / 85.929 | 119.053 / 117.918 | 92.462 / 92.411 | 0.932x / 0.930x |
| sieve | 3.230 / 3.236 | 3.233 / 3.244 | 3.349 / 3.333 | 5.809 / 5.820 | 0.557x / 0.557x |
| minimal | 5.103 / 5.095 | 5.109 / 5.115 | 7.255 / 7.202 | 5.920 / 5.898 | 0.863x / 0.867x |
| memset | 3.671 / 3.667 | 3.671 / 3.675 | 3.413 / 3.414 | 3.819 / 3.793 | 0.961x / 0.969x |
| init | 684.936 / 685.779 | 654.644 / 649.085 | 1320.409 / 1320.513 | 658.761 / 655.655 | 0.994x / 0.990x |
| tick | 28.936 / 28.690 | 29.012 / 28.883 | 84.064 / 84.465 | 33.665 / 33.930 | 0.862x / 0.851x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.206 | 17.880 | 12.085 | 602.601 | 53.711 | 20.002 | 0.008 |
| init/0/candidate | 7.370 | 18.974 | 12.023 | 572.396 | 53.749 | 20.064 | 0.008 |
| init/1/candidate | 7.406 | 19.638 | 11.872 | 566.984 | 53.873 | 20.099 | 0.007 |
| init/1/baseline | 7.666 | 19.314 | 11.973 | 603.527 | 53.834 | 20.130 | 0.007 |
| tick/0/baseline | 7.222 | 17.797 | 11.643 | 28.337 | 0.383 | 0.103 | 0.007 |
| tick/0/candidate | 7.482 | 18.636 | 11.110 | 28.375 | 0.391 | 0.102 | 0.007 |
| tick/1/candidate | 7.270 | 18.115 | 11.136 | 28.320 | 0.393 | 0.104 | 0.007 |
| tick/1/baseline | 7.414 | 18.671 | 10.844 | 28.211 | 0.379 | 0.100 | 0.007 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 732.262 | 690.836 | -5.66% |
| init/1 | 729.477 | 690.982 | -5.28% |
| tick/0 | 71.552 | 71.040 | -0.72% |
| tick/1 | 71.045 | 71.161 | +0.16% |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 200 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.
