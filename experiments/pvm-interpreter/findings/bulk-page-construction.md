# bulk-page-construction

Keep: checked bulk page construction reduces frame/reset cost and improves all six reused gameplay lifecycles by 16.8–18.0%; call-only execution is broadly unchanged. Retain initialization spread and small-workload caveats.

Checked macOS arm64 CPU durations. Baseline commit `b19262e59d3787cc9b72abccffff8f19c680ca3a`; candidate overlay
`684ad0ba7072322dbbeffffc61e9377546f722485932dfea325532ed2ce81f6e`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | +0.39% | +0.31% | -0.60…+1.57% |
| sieve | -0.04% | -0.16% | -0.14…+0.11% |
| minimal | +0.42% | -0.86% | -0.37…+2.24% |
| memset | -0.01% | +0.24% | -0.65…+3.05% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 729.519 | 727.383 | -0.29% | -1.42% |
| init cold/1 | 721.716 | 778.516 | +7.87% | +6.45% |
| init cold/2 | 724.353 | 721.255 | -0.43% | -1.97% |
| init cold/3 | 725.992 | 719.054 | -0.96% | -2.10% |
| init cold/4 | 719.523 | 733.099 | +1.89% | +0.66% |
| init cold/5 | 722.830 | 720.302 | -0.35% | -1.28% |
| init reused/0 | 715.034 | 764.126 | +6.87% | +5.54% |
| init reused/1 | 718.788 | 725.495 | +0.93% | -0.27% |
| init reused/2 | 722.848 | 726.759 | +0.54% | -0.68% |
| init reused/3 | 721.652 | 724.457 | +0.39% | -0.79% |
| init reused/4 | 722.714 | 723.809 | +0.15% | -1.01% |
| init reused/5 | 721.691 | 727.425 | +0.79% | -0.42% |
| tick cold/0 | 31.868 | 31.772 | -0.30% | -15.72% |
| tick cold/1 | 31.733 | 31.582 | -0.48% | -16.30% |
| tick reused/0 | 28.963 | 28.910 | -0.18% | -17.11% |
| tick reused/1 | 28.892 | 28.857 | -0.12% | -16.76% |
| tick reused/2 | 29.000 | 28.962 | -0.13% | -17.99% |
| tick reused/3 | 28.861 | 28.995 | +0.46% | -16.79% |
| tick reused/4 | 28.947 | 29.037 | +0.31% | -17.09% |
| tick reused/5 | 29.045 | 29.137 | +0.32% | -17.53% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 84.549 / 84.059 | 85.034 / 85.644 | 117.343 / 116.553 | 91.446 / 91.103 | 0.930x / 0.940x |
| sieve | 3.175 / 3.172 | 3.169 / 3.176 | 3.278 / 3.348 | 5.712 / 5.707 | 0.555x / 0.556x |
| minimal | 4.994 / 4.995 | 5.166 / 5.021 | 7.119 / 7.140 | 5.811 / 5.817 | 0.889x / 0.863x |
| memset | 3.596 / 3.632 | 3.650 / 3.655 | 3.398 / 3.398 | 3.812 / 3.813 | 0.957x / 0.959x |
| init | 715.034 / 718.788 | 764.126 / 725.495 | 1387.187 / 1325.629 | 668.137 / 666.414 | 1.144x / 1.089x |
| tick | 28.963 / 28.892 | 28.910 / 28.857 | 84.582 / 84.450 | 34.181 / 34.193 | 0.846x / 0.844x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.305 | 27.206 | 20.686 | 618.735 | 53.967 | 33.236 | 0.006 |
| init/0/candidate | 7.721 | 18.218 | 12.248 | 661.443 | 57.508 | 36.235 | 0.007 |
| init/1/candidate | 7.472 | 18.874 | 11.950 | 629.537 | 54.163 | 33.358 | 0.007 |
| init/1/baseline | 7.476 | 26.793 | 20.544 | 622.073 | 54.116 | 33.364 | 0.007 |
| tick/0/baseline | 7.492 | 27.182 | 19.994 | 28.473 | 0.394 | 0.099 | 0.006 |
| tick/0/candidate | 7.463 | 18.554 | 11.636 | 28.415 | 0.393 | 0.100 | 0.007 |
| tick/1/candidate | 7.390 | 18.899 | 11.664 | 28.372 | 0.393 | 0.097 | 0.007 |
| tick/1/baseline | 7.369 | 27.221 | 19.863 | 28.400 | 0.389 | 0.096 | 0.006 |

## Cold first-use scope

Plan + frame construction + reset + cold call + final publication. Fixture loading,
decoding/validation and final destruction are outside this explicitly measured scope.

| Phase/order | Parent ms | Candidate ms | Change |
| --- | ---: | ---: | ---: |
| init/0 | 791.864 | 769.448 | -2.83% |
| init/1 | 778.888 | 818.296 | +5.06% |
| init/2 | 789.342 | 762.715 | -3.37% |
| init/3 | 784.592 | 759.333 | -3.22% |
| init/4 | 777.669 | 774.330 | -0.43% |
| init/5 | 782.105 | 764.132 | -2.30% |
| tick/0 | 91.960 | 73.342 | -20.25% |
| tick/1 | 94.529 | 75.826 | -19.79% |

## Separate complete-process peak RSS

All clocks from these resource probes are discarded. RSS includes fixtures, validation
and every process owner; these are not engine-only allocation measurements.

| Phase/order/role | Peak MiB |
| --- | ---: |
| init/0/baseline | 270.22 |
| init/0/candidate | 270.22 |
| init/1/candidate | 270.22 |
| init/1/baseline | 270.22 |
| tick/0/baseline | 270.34 |
| tick/0/candidate | 270.34 |
| tick/1/candidate | 270.34 |
| tick/1/baseline | 270.34 |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 208 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.

## Interpretation

Retain this constructor change. The six gameplay lifecycle pairs improve16.76–17.99% (median
17.10%), while calls alone change +0.09%. Six reused init pairs change +0.67%call/-0.55%lifecycle;
there is no claim of an execution-kernel improvement. Cold init call/lifecycle medians over all
six retained pairs are -0.32%/-1.35%, including the original +7.87%call/+6.45%lifecycle pair.
Before/after snapshots for that pair show heavy Spotlight/browser activity; this is an observed
confound, not proof of the CPU cause, and the pair remains included. Four additional cold pairs
were declared as a fixed replication after the original complete cohort; none was selected out.

Pinky/sieve/Minimal/fill kernel medians are +0.39%/-0.04%/+0.42%/-0.01%; the corresponding
lifecycle medians are +0.31%/-0.16%/-0.86%/+0.24%. Small changes remain local variation, not
claimed wins or material regressions. Whole-process peak RSS stays within270.22–270.34MiB in
both roles. Constructors grow each full page only after checking native-int arithmetic, verify
successful growth, then copy the full4096bytes before observation. Mapping, source ownership,
region coalescing, checked accesses and immutable publication remain unchanged. Eight native and
eight ASan groups pass. All208timed processes,4negative controls and8separate RSS observations
are retained. The accepted source is the runtime committed with this finding.
