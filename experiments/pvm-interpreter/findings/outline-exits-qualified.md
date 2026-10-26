# outline-exits-qualified

Reject: rare exit/error outlining does not establish a useful consistent real-workload gain. Restore the runtime from the accepted checkpoint; retain the complete comparison and harness evidence.

Checked macOS arm64 CPU durations. Baseline commit `72c79e4d36ae9b51f5d3f971477f0bb4b144df7d`; candidate overlay
`7917152f891fba5929961de66df2fba2cf4290abcd418cd14d2b2121bb801d91`. All declared samples retained.

Fresh private-cache builds at identical source/output paths produce equal repeat images for
both roles and all three drivers. All timed calls validate complete CPU, gas, memory,
permissions, source snapshots and (for DOOM) host output. Negative fixtures reject.

## Repeated small workloads

Six matched orders per scope. Negative changes are faster. Lifecycle includes reset, call
and full immutable publication; constructor costs are separate.

| Guest | Kernel change | Lifecycle change | Kernel pair range |
| --- | ---: | ---: | ---: |
| pinky | +0.57% | +0.37% | -0.01…+1.18% |
| sieve | -0.74% | +0.74% | -4.31…+0.14% |
| minimal | +0.93% | +2.53% | -3.55…+3.75% |
| memset | +0.19% | -0.00% | -1.25…+1.91% |

## DOOM calls and measured lifecycle

| Scope/order | Parent call ms | Candidate call ms | Call change | Lifecycle change |
| --- | ---: | ---: | ---: | ---: |
| init cold/0 | 733.959 | 733.904 | -0.01% | +0.04% |
| init cold/1 | 734.883 | 736.104 | +0.17% | +0.19% |
| init reused/0 | 721.534 | 724.210 | +0.37% | +0.38% |
| init reused/1 | 718.460 | 721.452 | +0.42% | +0.46% |
| tick cold/0 | 31.417 | 32.913 | +4.76% | +4.45% |
| tick cold/1 | 32.688 | 31.637 | -3.22% | -2.21% |
| tick reused/0 | 28.869 | 29.276 | +1.41% | +1.15% |
| tick reused/1 | 29.034 | 29.072 | +0.13% | -0.14% |
| tick reused/2 | 29.056 | 29.419 | +1.25% | -0.08% |
| tick reused/3 | 28.869 | 29.277 | +1.41% | +0.60% |
| tick reused/4 | 28.543 | 29.172 | +2.20% | +1.34% |
| tick reused/5 | 29.022 | 29.456 | +1.50% | +1.21% |

## Call-only comparison in both process orders

The master control is the existing frozen prepared-interpreter image, not a new master
build. Reference constructors/reset/publication equivalents are unavailable; ratios below
compare calls only. Each cell is forward/reverse milliseconds.

| Workload | Parent | Candidate | Frozen master | PolkaVM interpreted | Candidate/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinky | 87.802 / 86.290 | 87.156 / 86.820 | 118.873 / 118.879 | 93.464 / 92.770 | 0.933x / 0.936x |
| sieve | 3.349 / 3.360 | 3.201 / 3.309 | 3.421 / 3.421 | 6.029 / 5.968 | 0.531x / 0.554x |
| minimal | 5.033 / 5.242 | 5.064 / 5.212 | 7.468 / 7.373 | 5.926 / 5.976 | 0.854x / 0.872x |
| memset | 3.640 / 3.659 | 3.675 / 3.643 | 3.552 / 3.531 | 3.946 / 3.937 | 0.931x / 0.925x |
| init | 721.534 / 718.460 | 724.210 / 721.452 | 1337.480 / 1337.319 | 677.751 / 678.601 | 1.069x / 1.063x |
| tick | 28.869 / 29.034 | 29.276 / 29.072 | 84.734 / 84.535 | 34.554 / 34.419 | 0.847x / 0.845x |

## Constructor and host phases

| Scope/order/role | Plan ms | Frame ms | Reset ms | Guest ms | Host ms | Resume ms | Final publication ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0/baseline | 7.618 | 28.885 | 20.750 | 625.409 | 54.718 | 33.623 | 0.006 |
| init/0/candidate | 7.238 | 27.160 | 20.915 | 627.449 | 54.832 | 33.894 | 0.006 |
| init/1/candidate | 7.808 | 28.614 | 20.465 | 624.781 | 54.404 | 33.461 | 0.006 |
| init/1/baseline | 7.802 | 27.946 | 20.640 | 623.011 | 53.959 | 33.151 | 0.006 |
| tick/0/baseline | 7.296 | 25.410 | 19.668 | 28.378 | 0.398 | 0.102 | 0.006 |
| tick/0/candidate | 7.281 | 26.031 | 19.657 | 28.790 | 0.385 | 0.099 | 0.006 |
| tick/1/candidate | 7.340 | 25.629 | 19.575 | 28.578 | 0.387 | 0.101 | 0.006 |
| tick/1/baseline | 7.282 | 25.760 | 19.739 | 28.546 | 0.384 | 0.100 | 0.007 |

Source-attempt and host-call counts remain exact: DOOM initialization 203,298,231 / 1,621;
gameplay 12,180,040 / 1. Source attempts are not native instructions. Small-driver node,
handler/argument and source-site byte counts are preserved in the accompanying JSON.

Process-load snapshots were taken before and after each child and retained in raw evidence.
They are time-averaged process CPU observations, not proof of uninterrupted host idleness;
no sample was automatically discarded. These are local timings, not hardware counters.

Completed 192 timed processes and 4 negative controls.
Full logs, source/fixture/image seals and disassembly remain in the ignored comparison directory.
The JSON preserves every accepted timing sample and phase; interpretation is scoped to this trial.

## Interpretation and restoration

Reject and restore the exact checkpoint runtime. Reused init regresses 0.37%/0.42%; all six
reused gameplay calls regress (median 1.41%), and Minimal lifecycle regresses 2.53% on its six
pairs. The static ARM64 charge body shrinks from 121 to 104 instructions, which does not imply
less executed work or faster CPU time. The three-pragmas trial is preserved in `outline-exits.patch`.
All source/check Nim files are byte-identical to checkpoint72c79e4d after restoration; its complete
native/ASan qualification is reused, not claimed as a new run.

The earlier diagnostic cohort is excluded in full. Its originating harness error assumed every
master single-call request emits one sample; frozen master gameplay actually emits thirteen.
An attempted log-reuse repair could mix metadata with overwritten reference logs, so that path
was removed and a complete clean cohort was measured. The exact qualified images were reused
only after proving byte equality and stable runtime/source/fixture seals. No individual outlier
was removed. Eight independent harness tests cover role counts, missing phase/source evidence,
assertion controls and absolute deadlines. Raw diagnostic failure evidence remains preserved.
